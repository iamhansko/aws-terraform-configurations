resource "aws_security_group" "vscode_ec2_security_group" {
  name        = var.security_group_name
  description = var.security_group_description
  vpc_id      = var.vpc_id
  tags = {
    Name = var.security_group_name
  }
}
# Standalone rule resources rather than inline ingress/egress blocks (rules.md F-2). Nothing adds
# rules to this group behind Terraform's back, so the usual reason does not apply - the reason
# this project does not use inline blocks does.
#
# The _monolithic template declared two inline ingress blocks here, for the moved SSH port and for
# code-server, and no egress block. CloudFormation's AWS::EC2::SecurityGroup leaves the allow-all
# egress rule EC2 attaches to every new group alone when a template names only
# SecurityGroupIngress, so the source template never had to spell outbound out. Terraform's inline
# blocks are attributes-as-blocks and authoritative over the whole group: omitting egress does not
# inherit that default, it revokes it.
#
# For this instance that is total. The bootstrap below downloads code-server from GitHub, the
# associations the root attaches pull container base images and clone a repository, and every AWS
# API call leaves through the same interface. With no egress rule the instance boots, apply reports
# success, and the log shows the wget timing out - the same failure that broke 101_ubuntu_xrdp.
resource "aws_vpc_security_group_ingress_rule" "vscode_ec2_code_server_ingress" {
  for_each = toset(var.ingress_cidr_blocks)

  security_group_id = aws_security_group.vscode_ec2_security_group.id
  description       = "code-server from ${each.value}"
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
resource "aws_vpc_security_group_egress_rule" "vscode_ec2_egress" {
  security_group_id = aws_security_group.vscode_ec2_security_group.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
resource "aws_iam_role" "vscode_ec2_iam_role" {
  name_prefix = var.iam_role_name_prefix
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
# for_each over the policy list rather than one attachment resource per policy, so a caller can
# add or remove a policy without this module changing (rules.md B-7). toset is safe because the
# ARNs are literal strings in configuration and so are known at plan time (rules.md B-8).
#
# This is the one role in the project that keeps a broad policy, and that is deliberate. rules.md
# A-5 narrows the automated roles; it excludes the workbench, because H-1's premise is that a
# person sits at this instance and runs whatever the demo needs from it - and here that includes
# docker build, ecr push, elbv2 register-targets, ecs describe-task-definition, s3 cp into the
# pipeline source bucket and a mysql client against Aurora. Guessing that list in advance produces
# an AccessDenied halfway through a demo.
resource "aws_iam_role_policy_attachment" "vscode_ec2_iam_role" {
  for_each   = toset(var.iam_policy_arns)
  role       = aws_iam_role.vscode_ec2_iam_role.name
  policy_arn = each.value
}
resource "aws_iam_instance_profile" "vscode_ec2_instance_profile" {
  name_prefix = var.iam_role_name_prefix
  # An instance profile holds at most one role, so this attribute is a single role name string -
  # not the list CloudFormation's AWS::IAM::InstanceProfile Roles property takes.
  # jsonencode([...]) here would send the literal string ["Ec2AdminRole-..."] as roleName, which
  # IAM rejects during apply while terraform validate and plan both pass, because the attribute is
  # a string either way (rules.md A-3). The conversion got this one right; the trap is listed here
  # because the next person editing this block is the one who would reintroduce it.
  role = aws_iam_role.vscode_ec2_iam_role.name
}
locals {
  # H-1 does not apply to this root, and it is worth saying so rather than leaving the absence to
  # be read as an oversight. That rule's five-tool list - code-server, kubectl, eksctl, helm,
  # docker - is conditional on the root also declaring an EKS cluster, because the tools exist to
  # drive one. There is no EKS cluster anywhere in this project; it is ECS on EC2 and Fargate. So
  # this module installs code-server, and the root injects the tools this demo actually needs
  # through additional_user_data: docker for the image build, git for the sources, jq and zip for
  # the CodePipeline artefact, and a mysql client for Aurora.
  user_data = <<-EOT
    #!/bin/bash
    set -x
    dnf update -yq
    dnf install -yq git
    dnf groupinstall -yq "Development Tools"
    dnf install -yq python${var.python_version}
    ln -sf /usr/bin/python${var.python_version} /usr/bin/python

    export VSC_VERSION="${var.code_server_version}"
    wget -q https://github.com/coder/code-server/releases/download/v$VSC_VERSION/code-server-$VSC_VERSION-linux-amd64.tar.gz
    tar -xzf code-server-$VSC_VERSION-linux-amd64.tar.gz
    mv code-server-$VSC_VERSION-linux-amd64 /usr/local/lib/code-server
    ln -sf /usr/local/lib/code-server/bin/code-server /usr/local/bin/code-server

    mkdir -p /home/ec2-user/.config/code-server
    cat <<'TFCODESERVERCONFIG' > /home/ec2-user/.config/code-server/config.yaml
    bind-addr: 0.0.0.0:${var.code_server_port}
    auth: none
    cert: false
    TFCODESERVERCONFIG
    chown -R ec2-user:ec2-user /home/ec2-user/.config

    cat <<'TFCODESERVERUNIT' > /etc/systemd/system/code-server.service
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

    # sshd moved off 22, as the _monolithic template had it, so that the only ports reachable are
    # the two this module's security group opens.
    #
    # A drop-in rather than the template's "sed -i 's/#Port 22/Port 22222/' /etc/ssh/sshd_config".
    # That substitution depends on the shipped config containing that exact commented line: AL2023
    # currently does, so it worked, but a release that drops the comment or writes "#Port  22"
    # turns the command into a silent no-op. sshd keeps listening on 22, which no security group
    # rule allows, and the instance looks unreachable over SSH for no visible reason. The drop-in
    # directory is included by the shipped config and does not depend on its contents.
    printf 'Port %s\n' ${var.ssh_port} > /etc/ssh/sshd_config.d/00-terraform-port.conf
    systemctl restart sshd

    ${var.additional_user_data}
    # The marker goes last, after additional_user_data (rules.md B-4). Touching it earlier would
    # release the associations the root chains off it while docker and the mysql client are still
    # installing, and the first of those associations runs docker build (rules.md H-2).
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
  associate_public_ip_address = var.associate_public_ip_address
  iam_instance_profile        = aws_iam_instance_profile.vscode_ec2_instance_profile.name
  vpc_security_group_ids      = concat([aws_security_group.vscode_ec2_security_group.id], var.extra_security_group_ids)
  user_data                   = local.user_data
  tags = {
    Name = var.instance_name
  }
  root_block_device {
    # The _monolithic template took the AL2023 default of 8 GiB and then had this instance build
    # four container images on it. Each one is an ubuntu base plus an 8 MB binary, and the build
    # cache holds every layer: the fourth push is where the disk runs out, and docker reports it as
    # a write error from the overlay driver rather than as a full filesystem.
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  # The role must already carry its managed policy before this instance boots. The instance profile
  # reference orders this after the profile and the role but not after the attachment - nothing
  # here refers to it - and the bootstrap starts calling AWS within seconds (rules.md D-1).
  depends_on = [aws_iam_role_policy_attachment.vscode_ec2_iam_role]
}
resource "aws_eip" "vscode_ec2_elastic_ip" {
  domain = "vpc"
  tags = {
    Name = var.instance_name
  }
}
# A separate association rather than the instance's own public IP, as the _monolithic template had
# it. The address then survives a stop and start of the instance, which the instance-assigned
# public IP does not - and the URL in the outputs and in the README on the instance is built from
# this one.
resource "aws_eip_association" "vscode_ec2_elastic_ip_association" {
  allocation_id = aws_eip.vscode_ec2_elastic_ip.allocation_id
  instance_id   = aws_instance.vscode_ec2.id
}
