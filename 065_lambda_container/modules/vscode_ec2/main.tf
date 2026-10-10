resource "aws_security_group" "vscode_ec2_security_group" {
  name        = var.security_group_name
  description = var.security_group_description
  vpc_id      = var.vpc_id
  tags = {
    Name = var.security_group_name
  }
}
# Standalone rule resources rather than the _monolithic template's inline dynamic "ingress" block
# (rules.md F-2), and the egress rule is a fix rather than a transcription.
#
# The template's group had one conditional ingress block - code-server from 0.0.0.0/0 when
# inbound_from_anywhere was "True" - and no egress. CloudFormation's AWS::EC2::SecurityGroup keeps the
# allow-all egress EC2 attaches to a new group when a template names no SecurityGroupEgress, so the source
# never had to spell outbound out. The AWS provider does the opposite on every VPC group it creates, inline
# blocks or not: it revokes that default rule straight after CreateSecurityGroup (the "NOTE on Egress rules"
# in the aws_security_group documentation). The converted group therefore had no egress whichever way the
# switch was set.
#
# For this instance that is total. Every useful line of the bootstrap goes outbound - dnf, the code-server
# tarball from GitHub, the Lambda base image from public ECR, pip, the ECR authorization token and the push.
# The instance still reaches "running", and the first sign of the problem is CreateFunction failing on an
# image that was never pushed - which says nothing about security groups.
resource "aws_vpc_security_group_egress_rule" "all_outbound" {
  security_group_id = aws_security_group.vscode_ec2_security_group.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
resource "aws_vpc_security_group_ingress_rule" "code_server_ingress" {
  for_each = toset(var.ingress_cidr_blocks)

  security_group_id = aws_security_group.vscode_ec2_security_group.id
  description       = "code-server from ${each.value}"
  ip_protocol       = "tcp"
  from_port         = var.code_server_port
  to_port           = var.code_server_port
  cidr_ipv4         = each.value
}
# Its own list, empty by default, because the _monolithic template opened no SSH port at all: it generated a
# key pair and never admitted a connection that could use it. Session Manager needs no inbound rule.
resource "aws_vpc_security_group_ingress_rule" "ssh_ingress" {
  for_each = toset(var.ssh_ingress_cidr_blocks)

  security_group_id = aws_security_group.vscode_ec2_security_group.id
  description       = "SSH from ${each.value}"
  ip_protocol       = "tcp"
  from_port         = var.ssh_port
  to_port           = var.ssh_port
  cidr_ipv4         = each.value
}
resource "aws_iam_role" "vscode_ec2_iam_role" {
  name_prefix = var.iam_name_prefix
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
# for_each over the policy list rather than one attachment resource per policy (rules.md B-7). toset is safe
# because the ARNs are literal strings in configuration and so are known at plan time (rules.md B-8).
resource "aws_iam_role_policy_attachment" "vscode_ec2_iam_role" {
  for_each   = toset(var.iam_policy_arns)
  role       = aws_iam_role.vscode_ec2_iam_role.name
  policy_arn = each.value
}
resource "aws_iam_instance_profile" "vscode_ec2_instance_profile" {
  name_prefix = var.iam_name_prefix
  # One role name string, not the list CloudFormation's AWS::IAM::InstanceProfile Roles property takes. The
  # conversion already had this right; jsonencode([...]) here would pass validate and plan and fail in IAM
  # during apply (rules.md A-3).
  role = aws_iam_role.vscode_ec2_iam_role.name
}
locals {
  # The base bootstrap: code-server and nothing project-specific. What this project builds on the instance
  # arrives through additional_user_data, so the module does not have to know about Lambda (rules.md B-4).
  user_data = <<-EOT
    #!/bin/bash
    set -x
    dnf update -yq
    dnf install -yq git
    dnf groupinstall -yq "Development Tools"
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
    ${var.additional_user_data}
    # The marker goes last, after additional_user_data (rules.md B-4). It replaces the template's
    # "/opt/aws/bin/cfn-signal -e $? --stack ... --resource VsCodeEc2", which could not have worked: there is
    # no CloudFormation stack to signal, and aws-cfn-bootstrap is not installed on Amazon Linux 2023.
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
    # Larger than the AL2023 default of 8 GiB the _monolithic template took. The Development Tools group, the
    # Lambda base image and the build cache all land on this disk.
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }
  # The role must carry its managed policy before this instance boots: the profile reference orders this
  # after the profile and the role but not after the attachment, and the bootstrap's ECR login runs within
  # minutes of launch. The egress rule is listed for the same reason - cloud-init starts downloading at once
  # (rules.md D-1).
  depends_on = [
    aws_iam_role_policy_attachment.vscode_ec2_iam_role,
    aws_vpc_security_group_egress_rule.all_outbound,
  ]

  lifecycle {
    # EC2 rejects user data over 16 KB at RunInstances, partway through an apply. length() counts characters,
    # which is bytes for this ASCII script.
    precondition {
      condition     = length(local.user_data) <= 16384
      error_message = "The rendered user_data exceeds the 16384 bytes EC2 accepts. additional_user_data is the part to shorten."
    }
  }
}
