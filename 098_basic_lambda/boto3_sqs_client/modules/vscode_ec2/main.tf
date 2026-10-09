# The workbench: code-server in a browser, plus the load generator that drives the function URL.
#
# The _monolithic template tagged this instance queue-bastion, and the module is deliberately not called
# bastion_ec2, because nothing bastions through it. Reading the two user data scripts settles it: this one
# installs code-server on 8000 with authentication disabled and writes the load generator into the home
# directory the IDE opens, and the worker instance's security group does allow SSH from this one's group - but
# the only inbound rule the template opened on this host was port 2222, which sshd is not listening on. There
# was no way in over SSH to jump from. What it actually is, is the human workbench for the demo, which is what
# rules.md H-1 and H-2 call a vscode_ec2 - and naming it that is what makes H-2's README obligation apply by
# name as well as by substance.
resource "aws_security_group" "vscode_ec2_security_group" {
  name        = var.security_group_name
  description = var.security_group_description
  vpc_id      = var.vpc_id
  tags = {
    Name = var.security_group_name
  }
}
# Standalone rule resources, never inline ingress/egress blocks (rules.md F-2).
#
# Nothing adds rules to this group behind Terraform's back - there is no controller in this project - so the
# usual reason does not apply. The reason that does is the egress rule below.
#
# CloudFormation's AWS::EC2::SecurityGroup leaves the VPC's default allow-all egress rule in place when a
# template names only SecurityGroupIngress, which is all this template named. Terraform does not: an
# aws_security_group always starts with its egress revoked, and inline blocks are authoritative over the whole
# group, so converting the ingress blocks without adding an egress rule does not inherit the default - it
# removes it. The group ends up with no outbound access at all.
#
# That failure is silent in the worst way. The apply succeeds, the instance reaches running, and every dnf,
# wget and pip line in the user data fails with a connection timeout - so code-server is simply never
# installed, port 8000 refuses every connection, and the only evidence is
# /var/log/cloud-init-output.log on a host that cannot be reached over 8000 either. This is the defect that
# broke 101_ubuntu_xrdp and appeared twice in 103_ecs_volumes; the conversion in _monolithic/main.tf already
# carries the fix and the note, and both directions are declared here for both groups in this project.
resource "aws_vpc_security_group_egress_rule" "vscode_ec2_egress" {
  security_group_id = aws_security_group.vscode_ec2_security_group.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
# for_each over the CIDR list rather than one rule per literal. toset is safe because these are configuration
# literals, known at plan time (rules.md B-7/B-8), and each.value in the description makes the plan say which
# source each rule is for.
resource "aws_vpc_security_group_ingress_rule" "vscode_ec2_code_server_ingress" {
  for_each = toset(var.ingress_cidr_blocks)

  security_group_id = aws_security_group.vscode_ec2_security_group.id
  description       = "code-server web UI from ${each.value}"
  ip_protocol       = "tcp"
  from_port         = var.code_server_port
  to_port           = var.code_server_port
  cidr_ipv4         = each.value
}
resource "aws_vpc_security_group_ingress_rule" "vscode_ec2_ssh_ingress" {
  for_each = toset(var.ingress_cidr_blocks)

  security_group_id = aws_security_group.vscode_ec2_security_group.id
  description       = "SSH from ${each.value}"
  ip_protocol       = "tcp"
  from_port         = var.ssh_port
  to_port           = var.ssh_port
  cidr_ipv4         = each.value
}
resource "aws_iam_role" "vscode_ec2_iam_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}
# One attachment resource for the whole list (rules.md B-7). The conversion had one resource per policy, which
# is fine for two and starts to drift as soon as a caller wants a third.
resource "aws_iam_role_policy_attachment" "vscode_ec2_iam_role" {
  for_each   = toset(var.iam_policy_arns)
  role       = aws_iam_role.vscode_ec2_iam_role.name
  policy_arn = each.value
}
resource "aws_iam_instance_profile" "vscode_ec2_instance_profile" {
  # A single role name, not the list CloudFormation's AWS::IAM::InstanceProfile Roles property takes - an
  # instance profile holds at most one role, so this attribute is a string. jsonencode([...]) here, which is
  # what the conversion produced before it was corrected in _monolithic/main.tf, sends the literal
  # ["terraform-..."] as roleName; IAM rejects that during apply while validate and plan both pass, because
  # the attribute is a string either way (rules.md A-3).
  role = aws_iam_role.vscode_ec2_iam_role.name
}
locals {
  # Written as one local rather than inline so the rendered script can be read in one place, and because
  # user_data is the longest thing in this module by far.
  #
  # The order matters in one place only: code-server is installed and started before pip runs, so a slow
  # wheel build does not delay the IDE coming up. Everything else is sequential because it has to be.
  user_data = <<-EOT
    #!/bin/bash
    set -x

    dnf update -yq
    dnf groupinstall -yq "Development Tools"
    dnf install -yq ${join(" ", var.python_packages)}

    # Deliberately no "ln -s /usr/bin/python3.13 /usr/bin/python3" here, which the _monolithic template ran
    # at this point. That command fails with "File exists", so it never did anything; forcing it with -f
    # would repoint the system interpreter and break dnf, whose own modules are installed for it. The
    # interpreter is named explicitly instead - see the python_command variable.

    export VSC_VERSION="${var.code_server_version}"
    wget -q https://github.com/coder/code-server/releases/download/v$VSC_VERSION/code-server-$VSC_VERSION-linux-amd64.tar.gz
    tar -xzf code-server-$VSC_VERSION-linux-amd64.tar.gz
    mv code-server-$VSC_VERSION-linux-amd64 /usr/local/lib/code-server
    # -f so a re-run of this script does not fail on an existing link.
    ln -sf /usr/local/lib/code-server/bin/code-server /usr/local/bin/code-server

    mkdir -p /home/ec2-user/.config/code-server
    # auth: none, as the _monolithic template configured it. Anyone who can reach code_server_port gets a
    # shell as ec2-user on a host whose role is AdministratorAccess, which is why ingress_cidr_blocks is
    # worth narrowing and why this is called out in that variable's description rather than only here.
    cat > /home/ec2-user/.config/code-server/config.yaml << 'CODESERVERCONFIG'
    bind-addr: 0.0.0.0:${var.code_server_port}
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
    # enable --now rather than the template's separate enable and start, which is the same thing in one call.
    systemctl enable --now code-server

    ${var.python_command} -m ensurepip --upgrade
    ${var.python_command} -m pip install --quiet ${join(" ", var.pip_packages)}

    %{if var.load_generator_script != null~}
    # A quoted heredoc delimiter, not echo with a single-quoted body: the generator's source contains
    # apostrophes and double quotes, and an unquoted delimiter would also let the shell expand anything
    # looking like a variable inside Python source. Terraform has already substituted every value it owns
    # before the shell sees this, so the shell has no reason to touch the body at all.
    #
    # rules.md A-4 is doubly important for this block. If this .tf file were saved with CRLF line endings the
    # terminator below would be TFLOADGEN\r, which the shell does not recognise - the heredoc would swallow
    # the rest of the script and nothing after this point would run, including the marker file that the
    # root's SSM associations wait for.
    cat > ${var.load_generator_path} << 'TFLOADGEN'
    ${var.load_generator_script}
    TFLOADGEN
    chown ec2-user:ec2-user ${var.load_generator_path}
    %{endif~}

    timedatectl set-timezone ${var.timezone}

    # No cfn-signal call, which the _monolithic template ended with. There is no CloudFormation stack here -
    # the conversion already notes that the CreationPolicy it signalled is not reproduced - and
    # aws-cfn-bootstrap is not installed on Amazon Linux 2023, so that line could only ever have failed with
    # "command not found" and left cloud-init recording a non-zero exit for the whole script.
    %{if var.additional_user_data != null~}
    ${var.additional_user_data}
    %{endif~}

    %{if var.marker_file_path != null~}
    mkdir -p ${var.marker_file_path}
    touch ${var.marker_file_path}/userdata
    %{endif~}
    EOT
}
resource "aws_instance" "vscode_ec2" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = var.key_name
  subnet_id              = var.subnet_id
  iam_instance_profile   = aws_iam_instance_profile.vscode_ec2_instance_profile.name
  vpc_security_group_ids = [aws_security_group.vscode_ec2_security_group.id]
  user_data              = local.user_data
  tags = {
    Name = var.instance_name
  }
  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_size
    encrypted   = true
  }
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = var.metadata_http_tokens
  }

  # The instance profile reference orders this after the profile and the role, and after nothing attached to
  # them (rules.md D-1). That matters more here than it usually does: the SSM agent starts within seconds of
  # boot and needs its permissions to register the instance, and an instance that comes up before the policy
  # lands may never appear as an SSM target - which the root's associations experience as a wait that ends in
  # a timeout rather than as a permissions error.
  depends_on = [aws_iam_role_policy_attachment.vscode_ec2_iam_role]
}
# An Elastic IP rather than the subnet's auto-assigned address.
#
# The code-server URL is printed as an output and written into a README on the instance itself, and an
# auto-assigned public address is released on stop and replaced on start - so both copies would point at
# someone else's instance after the first stop/start. The _monolithic template allocated one for the same
# reason, though its output returned the allocation id instead of the address: CloudFormation's Ref on an
# AWS::EC2::EIP returns the IP, so the conversion's blanket Ref -> .id mapping produced
# http://eipalloc-...:8000.
resource "aws_eip" "vscode_ec2" {
  count = var.associate_elastic_ip ? 1 : 0

  domain = "vpc"
  tags = {
    Name = var.instance_name
  }
}
resource "aws_eip_association" "vscode_ec2" {
  count = var.associate_elastic_ip ? 1 : 0

  allocation_id = aws_eip.vscode_ec2[0].allocation_id
  instance_id   = aws_instance.vscode_ec2.id
}
