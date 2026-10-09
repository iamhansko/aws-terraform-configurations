# The workbench: code-server in a browser, which is where the demo's curl and aws commands are meant to be
# run from.
#
# The _monolithic template tagged this instance bastion and named its security group bastion-sg, and the
# module is deliberately not called bastion_ec2 because nothing bastions through it. The userdata settles
# it: this host installs code-server on 8000 with authentication disabled and does nothing else, and the app
# server's security group in that template admitted the application port from 0.0.0.0/0 and opened no SSH
# port at all - so there was nothing to reach through here and no way to reach it. What it actually is, is
# the human workbench for the demo, which is what rules.md H-1 and H-2 call a vscode_ec2. Naming it that is
# also what makes H-2's README obligation apply by name as well as by substance.
#
# H-1's five-tool rule does not apply. It is conditioned on a root that also declares an EKS cluster, and
# this root declares a web ACL, a load balancer and two instances - there is no cluster anywhere in the
# project, so kubectl, eksctl, helm and docker would be four downloads with nothing to point at.
# code-server is installed; jq is added because the verification commands this project publishes return
# JSON and get-sampled-requests in particular is unreadable without it.
resource "aws_security_group" "vscode_ec2_security_group" {
  name        = var.security_group_name
  name_prefix = var.security_group_name == null ? var.security_group_name_prefix : null
  description = var.security_group_description
  vpc_id      = var.vpc_id
  tags = {
    Name = coalesce(var.security_group_name, var.security_group_name_prefix)
  }
}
# Standalone rule resources rather than inline ingress/egress blocks (rules.md F-2). Nothing adds rules to
# this group behind Terraform's back - there is no controller in this project - so the usual reason does not
# apply. The reason that does is the egress rule.
#
# The _monolithic template gave this group two inline ingress blocks, for 22 and 8000, and no egress block -
# as it did for all three of its groups. CloudFormation leaves EC2's default allow-all egress rule in place
# when a template names only SecurityGroupIngress; Terraform's inline blocks are attributes-as-blocks and
# authoritative over the whole group, so carrying the ingress across without adding egress does not inherit
# that default, it revokes it.
#
# On this host the result is an instance with no IDE. Every line of the bootstrap reaches the internet - dnf
# for the interpreter and jq, wget for the code-server tarball - so with egress revoked code-server is never
# installed, port 8000 refuses every connection, and the only evidence is /var/log/cloud-init-output.log on
# a host whose IDE is the way in. It also breaks the README this project writes onto the instance: the SSM
# agent needs outbound 443 to register, so the root's association waits for a marker that never appears and
# ends in a timeout rather than an error that names the cause.
#
# This defect broke 101_ubuntu_xrdp and was found twice in 103_ecs_volumes.
resource "aws_vpc_security_group_egress_rule" "vscode_ec2_egress" {
  security_group_id = aws_security_group.vscode_ec2_security_group.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
# for_each over the CIDR list rather than one rule per literal. toset() is correct because these are
# configuration literals and so are known at plan time (rules.md B-7/B-8), and each.value in the description
# makes a plan say which source each rule is for.
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
# One attachment resource for the whole list rather than one per policy (rules.md B-7). The conversion had a
# single attachment resource because the template attached a single policy; a list means a caller can add
# one without this module changing. toset() is safe because managed policy ARNs are configuration literals
# and are known at plan time (rules.md B-8).
resource "aws_iam_role_policy_attachment" "vscode_ec2_iam_role" {
  for_each   = toset(var.iam_policy_arns)
  role       = aws_iam_role.vscode_ec2_iam_role.name
  policy_arn = each.value
}
resource "aws_iam_instance_profile" "vscode_ec2_instance_profile" {
  # A single role name, not the list CloudFormation's AWS::IAM::InstanceProfile Roles property takes - an
  # instance profile holds at most one role, so this attribute is a string. jsonencode([...]) here sends the
  # literal ["terraform-..."] as roleName, which IAM rejects during apply while terraform validate and plan
  # both pass because the attribute is a string either way (rules.md A-3).
  role = aws_iam_role.vscode_ec2_iam_role.name
}
locals {
  # Written as one local rather than inline because user_data is the longest thing in this module by far.
  #
  # The order matters in one place: code-server is installed and started before ensurepip runs, so a slow
  # step does not delay the IDE coming up. The marker file is last, for the reason given at the bottom.
  user_data = <<-EOT
    #!/bin/bash
    set -x

    dnf update -yq
    %{if length(var.dnf_groups) > 0~}
    dnf groupinstall -yq ${join(" ", [for group in var.dnf_groups : "\"${group}\""])}
    %{endif~}
    dnf install -yq ${join(" ", var.dnf_packages)}

    # Deliberately no "ln -sf /usr/bin/python3.13 /usr/bin/python", which the _monolithic template ran here.
    # It succeeded, because /usr/bin/python does not exist on Amazon Linux 2023 - but dnf is itself a Python
    # program bound to the system interpreter, and a repointed python is a dnf that cannot import its own
    # modules on the next package install. The interpreter is named explicitly instead.

    export VSC_VERSION="${var.code_server_version}"
    wget -q https://github.com/coder/code-server/releases/download/v$VSC_VERSION/code-server-$VSC_VERSION-linux-amd64.tar.gz
    tar -xzf code-server-$VSC_VERSION-linux-amd64.tar.gz
    mv code-server-$VSC_VERSION-linux-amd64 /usr/local/lib/code-server
    # -f so that a re-run of this script does not fail on an existing link.
    ln -sf /usr/local/lib/code-server/bin/code-server /usr/local/bin/code-server

    mkdir -p /home/ec2-user/.config/code-server
    # auth: none, as the _monolithic template configured it. Anyone who can reach code_server_port gets a
    # shell as ec2-user on a host whose instance role is AdministratorAccess, which is why
    # ingress_cidr_blocks is worth narrowing - see that variable rather than relying on this comment.
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
    # enable --now rather than the template's separate enable and start, which is the same thing in one call.
    systemctl enable --now code-server

    ${var.python_command} -m ensurepip --upgrade

    timedatectl set-timezone ${var.timezone}

    # No cfn-signal call, which the _monolithic template ended with. There is no CloudFormation stack here -
    # the conversion's own comment notes that the CreationPolicy it signalled is not reproduced - and
    # aws-cfn-bootstrap is not installed on Amazon Linux 2023, so that line could only ever have failed with
    # "command not found" and left cloud-init recording a non-zero exit for the whole script.
    %{if var.additional_user_data != null~}
    ${var.additional_user_data}
    %{endif~}

    # Last, and that position is the point. The root's SSM association waits for this file before writing
    # the README, so a marker written before the steps above would start it while code-server is still
    # installing - and the README would land on a host with no IDE to read it in (rules.md B-4/D-5/H-2).
    %{if var.marker_file_path != null~}
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
  iam_instance_profile        = aws_iam_instance_profile.vscode_ec2_instance_profile.name
  vpc_security_group_ids      = [aws_security_group.vscode_ec2_security_group.id]
  user_data                   = local.user_data
  associate_public_ip_address = var.associate_public_ip_address

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
    # required, where the _monolithic template left the provider default of optional. Nothing on this host
    # reads the metadata service over IMDSv1: the SSM agent and the AWS CLI both handle the token
    # themselves, and there is no script here that curls the identity document - which is the one thing that
    # forced optional in 098_basic_lambda.
    http_tokens = var.metadata_http_tokens
  }

  # The instance profile reference orders this after the profile and the role, and after nothing attached to
  # them (rules.md D-1). It matters here more than usual: the SSM agent registers within seconds of boot and
  # needs its permissions to do so, and an instance that comes up before the policy lands may never appear
  # as an SSM target - which the root's association experiences as a wait that ends in a timeout rather than
  # as a permissions error.
  depends_on = [aws_iam_role_policy_attachment.vscode_ec2_iam_role]
}
# An optional Elastic IP, which the _monolithic template did not allocate.
#
# Off by default, so the instance behaves as the original did. It is here because of what H-2 does to this
# project: the code-server URL is both a Terraform output and a line inside a README written onto the
# instance's own disk, and an auto-assigned public address is released on stop and replaced on start - so
# after one stop/start both copies point at an address that now belongs to somebody else. Turning this on is
# the fix for a workbench that is going to be stopped overnight; leaving it off is right for a demo that is
# applied and destroyed in one sitting.
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
