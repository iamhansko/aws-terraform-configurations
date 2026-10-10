data "aws_ssm_parameter" "ami_id" {
  name = var.ami_ssm_parameter_name
}
# Standalone rule resources rather than inline ingress/egress blocks. Nothing adds rules to this group, so
# inline blocks would not break anything today - but a new group in this repository is written this way
# without exception, because the day something does add a rule, inline blocks silently revert it on the next
# apply (rules.md F-2).
resource "aws_security_group" "vscode_ec2_security_group" {
  description = "Security Group for the VS Code EC2 instance"
  name        = var.security_group_name
  vpc_id      = var.vpc_id
  tags = {
    Name = var.security_group_name
  }
}
resource "aws_vpc_security_group_ingress_rule" "code_server_from_anywhere" {
  count             = var.allow_inbound_from_anywhere ? 1 : 0
  security_group_id = aws_security_group.vscode_ec2_security_group.id
  description       = "code-server from anywhere"
  ip_protocol       = "tcp"
  from_port         = var.code_server_port
  to_port           = var.code_server_port
  cidr_ipv4         = "0.0.0.0/0"
}
resource "aws_vpc_security_group_ingress_rule" "code_server_from_prefix_list" {
  for_each          = toset(var.ingress_prefix_list_ids)
  security_group_id = aws_security_group.vscode_ec2_security_group.id
  description       = "code-server from a supplied managed prefix list"
  ip_protocol       = "tcp"
  from_port         = var.code_server_port
  to_port           = var.code_server_port
  prefix_list_id    = each.value
}
# Stated explicitly. The _monolithic template's group had no egress rule at all, and Terraform - unlike
# CloudFormation - removes the allow-all egress rule AWS puts on a new group, so that instance could not
# download code-server or reach SSM.
resource "aws_vpc_security_group_egress_rule" "all_outbound" {
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
# aws_iam_instance_profile.role takes a single role name, not the list that CloudFormation's
# AWS::IAM::InstanceProfile Roles property accepts (rules.md A-3).
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
  # No cfn-signal at the end, which the _monolithic template's script carried. There is no CloudFormation
  # stack to signal and aws-cfn-bootstrap is not installed on Amazon Linux 2023, so it only ever failed. The
  # completion marker below is what replaces it (rules.md B-4/D-5).
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
  # The instance profile's role must already carry its managed policies before the instance boots, otherwise
  # the bootstrap script's AWS calls fail with AccessDenied (rules.md D-1). The egress rule is listed for the
  # same reason: cloud-init starts downloading within seconds of launch.
  depends_on = [
    aws_iam_role_policy_attachment.vscode_ec2_iam_role,
    aws_vpc_security_group_egress_rule.all_outbound,
  ]
}
