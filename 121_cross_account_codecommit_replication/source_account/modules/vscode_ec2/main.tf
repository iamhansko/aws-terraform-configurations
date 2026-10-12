data "aws_ssm_parameter" "ami" {
  name = var.ami_ssm_parameter_name
}

resource "aws_security_group" "workbench" {
  name_prefix = var.security_group_name_prefix
  description = "Security group for the CodeCommit replication workbench"
  vpc_id      = var.vpc_id

  tags = {
    Name = var.security_group_name_prefix
  }
}

resource "aws_vpc_security_group_ingress_rule" "code_server_from_anywhere" {
  count = var.allow_inbound_from_anywhere ? 1 : 0

  security_group_id = aws_security_group.workbench.id
  description       = "code-server from anywhere"
  ip_protocol       = "tcp"
  from_port         = var.code_server_port
  to_port           = var.code_server_port
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "code_server_from_prefix_list" {
  for_each = toset(var.ingress_prefix_list_ids)

  security_group_id = aws_security_group.workbench.id
  description       = "code-server from a supplied managed prefix list"
  ip_protocol       = "tcp"
  from_port         = var.code_server_port
  to_port           = var.code_server_port
  prefix_list_id    = each.value
}

# Standalone rules keep the group compatible with other actors and make outbound bootstrap access explicit
# instead of depending on EC2's default rule (rules.md F-2).
resource "aws_vpc_security_group_egress_rule" "all_outbound" {
  security_group_id = aws_security_group.workbench.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_iam_role" "workbench" {
  name_prefix = "${var.name}-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "workbench" {
  for_each = toset(var.iam_policy_arns)

  role       = aws_iam_role.workbench.name
  policy_arn = each.value
}

resource "aws_iam_instance_profile" "workbench" {
  name_prefix = "${var.name}-"
  role        = aws_iam_role.workbench.name
}

resource "aws_instance" "workbench" {
  ami                         = data.aws_ssm_parameter.ami.insecure_value
  instance_type               = var.instance_type
  key_name                    = var.key_name
  iam_instance_profile        = aws_iam_instance_profile.workbench.name
  subnet_id                   = var.subnet_id
  associate_public_ip_address = var.associate_public_ip_address
  vpc_security_group_ids      = concat([aws_security_group.workbench.id], var.extra_security_group_ids)

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  user_data = <<-EOT
    #!/bin/bash
    set -euxo pipefail
    dnf update -yq
    dnf install -yq git tar wget

    export VSC_VERSION="${var.code_server_version}"
    wget -q https://github.com/coder/code-server/releases/download/v$VSC_VERSION/code-server-$VSC_VERSION-linux-amd64.tar.gz
    tar -xzf code-server-$VSC_VERSION-linux-amd64.tar.gz
    mv code-server-$VSC_VERSION-linux-amd64 /usr/local/lib/code-server
    ln -sf /usr/local/lib/code-server/bin/code-server /usr/local/bin/code-server

    mkdir -p /home/ec2-user/.config/code-server
    cat > /home/ec2-user/.config/code-server/config.yaml << 'CODE_SERVER_CONFIG'
    bind-addr: 0.0.0.0:${var.code_server_port}
    auth: none
    cert: false
    CODE_SERVER_CONFIG
    chown -R ec2-user:ec2-user /home/ec2-user/.config

    cat > /etc/systemd/system/code-server.service << 'CODE_SERVER_SERVICE'
    [Unit]
    Description=VS Code Server
    After=network.target

    [Service]
    Type=simple
    User=ec2-user
    ExecStart=/usr/local/lib/code-server/bin/code-server --config /home/ec2-user/.config/code-server/config.yaml /home/ec2-user
    Restart=always

    [Install]
    WantedBy=multi-user.target
    CODE_SERVER_SERVICE
    systemctl daemon-reload
    systemctl enable --now code-server

    ${var.additional_user_data}
    %{if var.marker_file_path != null~}
    mkdir -p ${var.marker_file_path}
    touch ${var.marker_file_path}/userdata
    %{endif~}
    EOT

  tags = {
    Name = var.name
  }

  # Attachments and outbound access must exist before cloud-init starts its AWS and network calls
  # (rules.md D-1/F-2).
  depends_on = [
    aws_iam_role_policy_attachment.workbench,
    aws_vpc_security_group_egress_rule.all_outbound,
  ]
}
