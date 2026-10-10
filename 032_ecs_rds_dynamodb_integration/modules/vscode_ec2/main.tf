# Standalone rule resources rather than inline ingress/egress blocks (rules.md F-2), and the egress rule is
# the single most consequential line in this module.
#
# The _monolithic template gave this group two inline ingress blocks - 22 and 8000 from anywhere - and no
# egress block at all. In CloudFormation an AWS::EC2::SecurityGroup only takes over the rules the template
# names, so the allow-all egress rule EC2 attaches to a new group stays in place. Terraform's inline
# ingress/egress are attributes-as-blocks and authoritative over the whole group, so naming any rule
# revokes it.
#
# For this instance that removes everything it exists to do. dnf cannot reach a repository, the code-server
# tarball cannot be downloaded, the SSM agent cannot reach ssmmessages (so every association below it in
# the chain never runs), the ECR token cannot be fetched and no image can be pushed. None of that reports
# an error in Terraform: apply succeeds, the instance reaches "running", and the first visible symptom is
# three ECS services whose tasks stop with CannotPullContainerError against images that were never built.
resource "aws_security_group" "vscode_ec2_security_group" {
  name        = var.security_group_name
  description = var.security_group_description
  vpc_id      = var.vpc_id
  tags = {
    Name = var.security_group_name
  }
}
resource "aws_vpc_security_group_egress_rule" "all_outbound" {
  security_group_id = aws_security_group.vscode_ec2_security_group.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
# code-server, reachable from anywhere by default because that is what the _monolithic template declared and
# it is the only way in to the workbench. See the variable for what that exposes.
resource "aws_vpc_security_group_ingress_rule" "code_server_from_anywhere" {
  count             = var.allow_inbound_from_anywhere ? 1 : 0
  security_group_id = aws_security_group.vscode_ec2_security_group.id
  description       = "code-server from anywhere"
  ip_protocol       = "tcp"
  from_port         = var.code_server_port
  to_port           = var.code_server_port
  cidr_ipv4         = "0.0.0.0/0"
}
# for_each over the CIDR list rather than one resource per source. These are literals in configuration, so
# toset is safe - unlike a security group ID arriving from another module (rules.md B-8).
resource "aws_vpc_security_group_ingress_rule" "ssh_ingress" {
  for_each          = toset(var.ssh_ingress_cidr_blocks)
  security_group_id = aws_security_group.vscode_ec2_security_group.id
  description       = "SSH from ${each.value}"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
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
      Action = ["sts:AssumeRole"]
    }]
  })
}
# One for_each attachment rather than the numbered resources the conversion produced (rules.md B-7). toset
# is safe because the ARNs are literal strings in configuration and known at plan time (rules.md B-8).
resource "aws_iam_role_policy_attachment" "vscode_ec2_iam_role" {
  for_each   = toset(var.iam_policy_arns)
  role       = aws_iam_role.vscode_ec2_iam_role.name
  policy_arn = each.value
}
resource "aws_iam_instance_profile" "vscode_ec2_instance_profile" {
  # An instance profile holds at most one role, so this is a single role name string - not the list
  # CloudFormation's AWS::IAM::InstanceProfile Roles property takes. jsonencode([...]) here sends the
  # literal string ["terraform-..."] as roleName, which IAM rejects during apply while validate and plan
  # both pass because the attribute is a string either way (rules.md A-3).
  role = aws_iam_role.vscode_ec2_iam_role.name
}
locals {
  # What the two cfn-init calls were supposed to do, done by the shell instead.
  #
  # The _monolithic template's userdata was three dnf lines followed by:
  #
  #   /opt/aws/bin/cfn-init -v --stack <name> --resource BastionEc2 --configsets init   --region ...
  #   /opt/aws/bin/cfn-init -v --stack <name> --resource BastionEc2 --configsets docker --region ...
  #   /opt/aws/bin/cfn-signal -e $? --stack <name> --resource BastionEc2 --region ...
  #
  # cfn-init reads the AWS::CloudFormation::Init metadata of a named resource in a live CloudFormation
  # stack. There is no stack, so both calls fail and everything they were the delivery mechanism for never
  # happens: the Development Tools group and Python, code-server itself, docker, the ECR login, the three
  # Go applications and the three docker build/push pairs. The three ECS services then reference images
  # that do not exist. That is the whole project, and it failed silently - cfn-init's commands all carried
  # ignoreErrors: true, so even in a real stack nothing would have stopped.
  #
  # Split in two here, deliberately. This script is the part that is the same for any workbench - python,
  # code-server, and the tools the caller asks for through additional_user_data. The part that needs to know
  # about ECR repositories and application source trees is not in userdata at all: it is in SSM associations
  # the root creates, because userdata has a 16 KB limit that three Go programs do not fit inside, and
  # because an association reports its exit status where a person can read it while userdata does not.
  #
  # set -x and no set -e, as the original effectively had with ignoreErrors. Everything lands in
  # /var/log/cloud-init-output.log, which is the first place to look when code-server does not answer. Not
  # adding set -e is a decision: with it, one failed download stops the script before the marker file and
  # every association waiting on that marker then sits until its own timeout with nothing to say. Without
  # it the script always reaches the marker, and the associations' own checks are what decide whether the
  # work actually succeeded.
  user_data = <<-EOT
    #!/bin/bash
    set -x
    timedatectl set-timezone ${var.timezone}
    dnf update -yq
    dnf install -yq git

    # The pythonInstall config set. ensurepip rather than dnf install python3-pip, as the original had it.
    dnf groupinstall -yq "Development Tools"
    dnf install -yq python${var.python_version}
    ln -sf /usr/bin/python${var.python_version} /usr/bin/python
    /usr/bin/python${var.python_version} -m ensurepip --upgrade

    # The vscodeInstall config set.
    export VSC_VERSION="${var.code_server_version}"
    wget -q https://github.com/coder/code-server/releases/download/v$VSC_VERSION/code-server-$VSC_VERSION-linux-amd64.tar.gz
    tar -xzf code-server-$VSC_VERSION-linux-amd64.tar.gz
    mv code-server-$VSC_VERSION-linux-amd64 /usr/local/lib/code-server
    ln -s /usr/local/lib/code-server/bin/code-server /usr/local/bin/code-server
    mkdir -p /home/ec2-user/.config/code-server
    cat > /home/ec2-user/.config/code-server/config.yaml << 'TFCODESERVERCONFIG'
    bind-addr: 0.0.0.0:${var.code_server_port}
    auth: none
    cert: false
    TFCODESERVERCONFIG
    chown -R ec2-user:ec2-user /home/ec2-user/.config
    cat > /etc/systemd/system/code-server.service << 'TFCODESERVERUNIT'
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
    TFCODESERVERUNIT
    systemctl daemon-reload
    systemctl enable --now code-server
    ${var.additional_user_data}
    %{if var.marker_file_path != null~}
    # The last thing the script does, and the replacement for cfn-signal (rules.md B-4).
    #
    # cfn-signal is dropped rather than translated: there is nothing to signal, and on Amazon Linux 2023
    # aws-cfn-bootstrap is not installed, so /opt/aws/bin/cfn-signal does not exist and the line only ever
    # produced "No such file or directory".
    #
    # Written after additional_user_data, not before. Everything waiting on this marker is waiting for the
    # tools the caller installs there - docker for the image builds, the mysql client for the schema step -
    # so a marker written earlier would let those associations start against an instance that has neither
    # (rules.md H-2).
    mkdir -p ${var.marker_file_path}
    touch ${var.marker_file_path}/userdata
    %{endif~}
    EOT
}
resource "aws_instance" "vscode_ec2" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  key_name                    = var.key_name
  subnet_id                   = var.subnet_id
  associate_public_ip_address = var.associate_public_ip_address
  iam_instance_profile        = aws_iam_instance_profile.vscode_ec2_instance_profile.name
  user_data                   = local.user_data
  vpc_security_group_ids      = concat([aws_security_group.vscode_ec2_security_group.id], var.extra_security_group_ids)
  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
    encrypted   = true
  }
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }
  tags = {
    Name = var.name
  }
  # cloud-init starts downloading within seconds of launch and the builds that follow call ECR, so both of
  # these have to be in place before the instance boots and neither is implied by a reference in this
  # resource (rules.md D-1).
  depends_on = [
    aws_iam_role_policy_attachment.vscode_ec2_iam_role,
    aws_vpc_security_group_egress_rule.all_outbound,
  ]
}
