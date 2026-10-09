# The workbench: a single instance in a private subnet of the spoke VPC, whose only route off the VPC is
# the transit gateway and therefore the firewall. Everything this project demonstrates is observed from
# here.
#
# The _monolithic template tagged it app-bastion. The module is not called bastion_ec2 because nothing
# bastions through it: there is no internet gateway in this VPC, so there is no address to open an inbound
# connection to, and the template opened no inbound port anyway - it attached the VPC's default security
# group, whose only inbound rule admits the group itself. What it actually is, is the human workbench for
# the demo, which is what rules.md H-1 and H-2 call a vscode_ec2 - and naming it that is what makes H-2's
# README obligation apply by name as well as by substance.
#
# H-1's five-tool rule does not apply. That rule is about a root that declares an EKS cluster alongside the
# workbench, and it requires kubectl, eksctl, helm and docker on top of code-server. There is no EKS
# cluster anywhere in this project, so none of those four are installed; adding kubectl here would be four
# minutes of bootstrap for a binary with no API server to talk to.
#
# How the IDE is reached, since there is no public address: Session Manager port forwarding. The agent on
# the instance opens a connection to its own loopback address and the session carries it back, so the
# browser connects to localhost. That is why code_server_bind_address defaults to loopback and why the
# security group has no inbound rule by default.
resource "aws_security_group" "vscode_ec2_security_group" {
  name        = var.security_group_name
  description = var.security_group_description
  vpc_id      = var.vpc_id
  tags = {
    Name = var.security_group_name
  }
}
# Standalone rule resources, never inline ingress/egress blocks (rules.md F-2). Nothing adds rules to this
# group behind Terraform's back - there is no load balancer controller in this project - so the usual
# reason does not apply. The reason that does is the egress rule below, and in this project it is the
# single most dangerous step of the whole conversion.
#
# The _monolithic template created no security group at all:
#
#   vpc_security_group_ids = [aws_vpc.app_vpc.default_security_group_id]
#
# A VPC's default group carries an allow-all egress rule, so the original had unrestricted outbound access
# without a line of configuration saying so. Giving the instance its own named group - which is worth doing,
# because the default group is shared by everything in the VPC and widening it widens everything - makes
# that implicit rule disappear. AWS attaches an allow-all egress rule to every new security group and the
# provider immediately revokes it; inline ingress/egress blocks are authoritative over the whole group, so
# a group that names only ingress does not inherit the default, it loses egress entirely.
#
# Here that is worse than the usual version of this bug. The instance is in a VPC with no internet gateway,
# so outbound traffic through the transit gateway and the firewall is the only traffic it has. Without this
# rule the apply succeeds, the instance reaches running, cloud-init's dnf and wget calls all time out,
# code-server is never installed, and the firewall logs stay empty - which reads as "the firewall is
# dropping everything" rather than "nothing ever left the instance". The project exists to demonstrate
# inspected egress, so the demo would silently prove nothing.
#
# 096_s3_static_website and 100_iam_roles_anywhere hit exactly this; 101_ubuntu_xrdp hit it in the form
# where the missing packages were the ones serving the port being tested.
resource "aws_vpc_security_group_egress_rule" "vscode_ec2_egress" {
  for_each = toset(var.egress_cidr_blocks)

  security_group_id = aws_security_group.vscode_ec2_security_group.id
  description       = "All outbound to ${each.value}, inspected by the firewall before it leaves"
  ip_protocol       = "-1"
  cidr_ipv4         = each.value
}
# Normally empty - see ingress_cidr_blocks. toset is safe because these are configuration literals, known
# at plan time (rules.md B-7/B-8), and each.value in the description makes the plan say which source each
# rule is for.
resource "aws_vpc_security_group_ingress_rule" "vscode_ec2_code_server_ingress" {
  for_each = toset(var.ingress_cidr_blocks)

  security_group_id = aws_security_group.vscode_ec2_security_group.id
  description       = "code-server web UI from ${each.value}"
  ip_protocol       = "tcp"
  from_port         = var.code_server_port
  to_port           = var.code_server_port
  cidr_ipv4         = each.value
}
resource "aws_iam_role" "vscode_ec2_iam_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["ec2.amazonaws.com"]
      }
      Action = "sts:AssumeRole"
    }]
  })
}
# One attachment resource for the whole list rather than one per policy (rules.md B-7). toset is safe
# because the ARNs are configuration literals and are known at plan time (rules.md B-8).
resource "aws_iam_role_policy_attachment" "vscode_ec2_iam_role" {
  for_each   = toset(var.iam_policy_arns)
  role       = aws_iam_role.vscode_ec2_iam_role.name
  policy_arn = each.value
}
resource "aws_iam_instance_profile" "vscode_ec2_instance_profile" {
  # An instance profile holds at most one role, so this attribute is a single role name string - not the
  # list CloudFormation's AWS::IAM::InstanceProfile Roles property takes. jsonencode([...]) here sends the
  # literal string ["terraform-..."] as roleName, which IAM rejects during apply while terraform validate
  # and plan both pass, because the attribute is a string either way (rules.md A-3).
  #
  # The _monolithic template already had this right, and the note is carried forward because the next
  # CloudFormation conversion will not: the same list-to-scalar reduction catches aws_sqs_queue_policy's
  # queue_url and aws_sns_topic_policy's arn, and grepping for "role = jsonencode([" misses both.
  role = aws_iam_role.vscode_ec2_iam_role.name
}
locals {
  # Written as one local rather than inline so the rendered script can be read in one place.
  #
  # Every network call below goes out through the transit gateway, the firewall endpoint in this instance's
  # zone, and that zone's NAT gateway. None of it works until the root's routes, the transit gateway
  # attachments and the firewall endpoints all exist, which is why the root orders this module after them
  # explicitly rather than relying on value references (rules.md D-2).
  #
  # One call that does not take that path, and it matters: name resolution. The spoke VPC has
  # enable_dns_support on, so the resolver is the VPC base address plus two, which matches the local route
  # and never reaches the firewall. That is the only reason this script runs at all, given that the policy
  # drops DNS on port 53 - and it is also what makes the DNS half of the demo legible, because the same
  # query answered locally and dropped when sent to a public resolver is the difference between "DNS is
  # broken" and "the firewall is in the path".
  user_data = <<-EOT
    #!/bin/bash
    set -x

    dnf update -yq
    dnf install -yq ${join(" ", var.dnf_packages)}

    export VSC_VERSION="${var.code_server_version}"
    wget -q https://github.com/coder/code-server/releases/download/v$VSC_VERSION/code-server-$VSC_VERSION-linux-amd64.tar.gz
    tar -xzf code-server-$VSC_VERSION-linux-amd64.tar.gz
    mv code-server-$VSC_VERSION-linux-amd64 /usr/local/lib/code-server
    # -f so a re-run of this script does not fail on an existing link.
    ln -sf /usr/local/lib/code-server/bin/code-server /usr/local/bin/code-server

    mkdir -p /home/ec2-user/.config/code-server
    # auth: none. The listener is on ${var.code_server_bind_address}, which by default is loopback, so the
    # only way to it is the Session Manager port forward - a connection that is already authenticated and
    # authorized by IAM before it reaches this port. Widening the bind address without adding
    # authentication offers an unauthenticated shell to anything that can route here.
    cat > /home/ec2-user/.config/code-server/config.yaml << 'CODESERVERCONFIG'
    bind-addr: ${var.code_server_bind_address}:${var.code_server_port}
    auth: none
    cert: false
    CODESERVERCONFIG
    chown -R ec2-user:ec2-user /home/ec2-user/.config

    cat > /etc/systemd/system/code-server.service << 'CODESERVERUNIT'
    [Unit]
    Description=VS Code Server
    After=network.target
    [Service]
    Type=simple
    User=ec2-user
    ExecStart=/usr/local/bin/code-server --config /home/ec2-user/.config/code-server/config.yaml /home/ec2-user
    Restart=always
    [Install]
    WantedBy=multi-user.target
    CODESERVERUNIT
    systemctl daemon-reload
    systemctl enable --now code-server

    timedatectl set-timezone ${var.timezone}

    # No cfn-signal call, which the _monolithic template ended with:
    #
    #   /opt/aws/bin/cfn-signal -e $? --stack <stack> --resource BastionEc2 --region <region>
    #
    # There is no CloudFormation stack here - the conversion itself notes that the CreationPolicy that
    # signal was answering is not reproduced - and aws-cfn-bootstrap is not installed on Amazon Linux
    # 2023, so that line could only ever have failed with "command not found" and left cloud-init
    # recording a non-zero exit for the whole script.
    %{if var.additional_user_data != null~}
    ${var.additional_user_data}
    %{endif~}

    # Last, so that the root's association starts only once everything above has finished (rules.md
    # D-5/H-2).
    #
    # rules.md A-4 is doubly important for a script this long. If this .tf file were saved with CRLF line
    # endings, every quoted heredoc terminator above would become CODESERVERCONFIG\r or CODESERVERUNIT\r,
    # which the shell does not recognise - the heredoc would swallow the rest of the script, nothing after
    # it would run, and the marker below would never appear. The association would then fail with
    # "unexpected state 'Failed'" and an execution time of a hundredth of a second, which is the signature
    # of a parse failure rather than a command that ran.
    %{if var.marker_file_path != null~}
    mkdir -p ${var.marker_file_path}
    touch ${var.marker_file_path}/userdata
    %{endif~}
    EOT
}
resource "aws_instance" "vscode_ec2" {
  ami                  = var.ami_id
  instance_type        = var.instance_type
  key_name             = var.key_name
  subnet_id            = var.subnet_id
  iam_instance_profile = aws_iam_instance_profile.vscode_ec2_instance_profile.name
  # The module's own group plus anything the caller added (rules.md B-6). The _monolithic template put the
  # VPC's default group here instead - see the comment on the egress rule above.
  vpc_security_group_ids = concat([aws_security_group.vscode_ec2_security_group.id], var.extra_security_group_ids)
  user_data              = local.user_data
  tags = {
    Name = var.instance_name
  }
  # No associate_public_ip_address and no Elastic IP, deliberately, and not only because the subnet is
  # private. An Elastic IP cannot be associated with an instance in a VPC that has no internet gateway
  # attached, so the allocation would fail; and a public address on this instance would be a path to the
  # internet that does not pass the firewall, which is the one thing this project must not have.
  root_block_device {
    volume_type = var.root_volume_type
    volume_size = var.root_volume_size
    encrypted   = var.root_volume_encrypted
  }
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = var.metadata_http_tokens
  }

  # The instance profile reference orders this after the profile and the role, and after nothing attached
  # to them (rules.md D-1). That matters more here than usual: the SSM agent starts within seconds of boot
  # and needs its permissions to register, and an instance that comes up before the policy lands may never
  # appear as an SSM target - which the root's association experiences as a wait that ends in a timeout
  # rather than as a permissions error, and which also removes the only way to reach the IDE.
  depends_on = [aws_iam_role_policy_attachment.vscode_ec2_iam_role]
}
