data "aws_ssm_parameter" "ami_id" {
  name = var.ami_ssm_parameter_name
}
resource "aws_security_group" "vscode_ec2_security_group" {
  description = "Security Group for the VS Code EC2 instance"
  name        = var.security_group_name
  vpc_id      = var.vpc_id
  tags = {
    Name = var.security_group_name
  }
}
# Standalone rule resources rather than inline ingress/egress blocks (rules.md F-2). This module already
# owned the selected ingress as a standalone address, so count remains one and changing the switch updates
# only its CIDR: My IP /32 by default, or 0.0.0.0/0 by explicit opt-in.
resource "aws_vpc_security_group_ingress_rule" "vscode_ec2_anywhere_ingress" {
  count             = 1
  security_group_id = aws_security_group.vscode_ec2_security_group.id
  description       = var.allow_inbound_from_anywhere ? "code-server from anywhere" : "code-server from My IP"
  ip_protocol       = "tcp"
  from_port         = var.code_server_port
  to_port           = var.code_server_port
  cidr_ipv4         = var.allow_inbound_from_anywhere ? "0.0.0.0/0" : var.my_ip_cidr
}
# count over the list's length rather than for_each over its values: a prefix list ID is usually a
# data source's result, and its length is known at plan time even when its value is not (rules.md B-8).
resource "aws_vpc_security_group_ingress_rule" "vscode_ec2_prefix_list_ingress" {
  count             = length(var.ingress_prefix_list_ids)
  security_group_id = aws_security_group.vscode_ec2_security_group.id
  description       = "code-server from a supplied managed prefix list"
  ip_protocol       = "tcp"
  from_port         = var.code_server_port
  to_port           = var.code_server_port
  prefix_list_id    = var.ingress_prefix_list_ids[count.index]
}
# Without an inline egress block the provider revokes the default allow-all egress rule when it creates
# the group, so this rule is what gives the instance a way out - the instance below waits for it.
resource "aws_vpc_security_group_egress_rule" "vscode_ec2_egress" {
  security_group_id = aws_security_group.vscode_ec2_security_group.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
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
resource "aws_iam_role_policy_attachment" "vscode_ec2_iam_role" {
  for_each   = toset(var.iam_policy_arns)
  role       = aws_iam_role.vscode_ec2_iam_role.name
  policy_arn = each.value
}
# aws_iam_instance_profile.role takes a single role name, not the list that
# CloudFormation's AWS::IAM::InstanceProfile Roles property accepts
# (rules.md A-3).
resource "aws_iam_instance_profile" "vscode_ec2_instance_profile" {
  role = aws_iam_role.vscode_ec2_iam_role.name
}
resource "aws_instance" "vscode_ec2" {
  ami                  = data.aws_ssm_parameter.ami_id.insecure_value
  instance_type        = var.instance_type
  key_name             = var.key_name
  iam_instance_profile = aws_iam_instance_profile.vscode_ec2_instance_profile.name
  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
    encrypted   = true
  }
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }
  user_data                   = <<-EOT
    #!/bin/bash
    set -x
    dnf update -yq
    dnf install -yq git
    dnf groupinstall -yq "Development Tools"
    export VSC_VERSION="${var.code_server_version}"
    wget -q https://github.com/coder/code-server/releases/download/v$VSC_VERSION/code-server-$VSC_VERSION-linux-amd64.tar.gz
    tar -xzf code-server-$VSC_VERSION-linux-amd64.tar.gz
    mv code-server-$VSC_VERSION-linux-amd64 /usr/local/lib/code-server
    ln -s /usr/local/lib/code-server/bin/code-server /usr/local/bin/code-server
    mkdir -p /home/ec2-user/.config/code-server
    cat <<EOF > /home/ec2-user/.config/code-server/config.yaml
    bind-addr: 0.0.0.0:${var.code_server_port}
    auth: none
    cert: false
    EOF
    chown -R ec2-user:ec2-user /home/ec2-user/.config
    cat <<EOF > /etc/systemd/system/code-server.service
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
    EOF
    systemctl daemon-reload
    systemctl enable --now code-server
    ${var.additional_user_data}
    %{if var.marker_file_path != null~}
    mkdir -p ${var.marker_file_path}
    touch ${var.marker_file_path}/userdata
    %{endif~}
    EOT
  subnet_id                   = var.subnet_id
  associate_public_ip_address = var.associate_public_ip_address
  vpc_security_group_ids      = concat([aws_security_group.vscode_ec2_security_group.id], var.extra_security_group_ids)
  tags = {
    Name = var.name
  }
  # The instance profile's role must already carry its managed policies before
  # the instance boots, otherwise the bootstrap script's AWS calls fail with
  # AccessDenied (rules.md D-1). The egress rule for the same reason: the group
  # is created with no outbound rule at all, and the bootstrap's first act is a
  # dnf update - nothing else orders the instance after a separate rule resource.
  depends_on = [
    aws_iam_role_policy_attachment.vscode_ec2_iam_role,
    aws_vpc_security_group_egress_rule.vscode_ec2_egress,
  ]
}
