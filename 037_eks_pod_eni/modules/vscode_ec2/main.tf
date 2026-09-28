data "aws_ssm_parameter" "ami_id" {
  name = var.ami_ssm_parameter_name
}

resource "aws_security_group" "vscode_ec2_security_group" {
  description = "Security Group"
  name        = "bastion-sg"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = var.allow_inbound_from_anywhere ? [1] : []
    content {
      protocol    = "tcp"
      from_port   = 8000
      to_port     = 8000
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  tags = {
    Name = "bastion-sg"
  }
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

resource "aws_iam_instance_profile" "vscode_ec2_instance_profile" {
  role = aws_iam_role.vscode_ec2_iam_role.name
}

resource "aws_instance" "vscode_ec2" {
  ami                  = data.aws_ssm_parameter.ami_id.insecure_value
  instance_type        = var.instance_type
  key_name             = var.key_name
  iam_instance_profile = aws_iam_instance_profile.vscode_ec2_instance_profile.name

  user_data = <<-EOT
    #!/bin/bash
    dnf update -yq
    dnf install -yq git
    dnf groupinstall -yq "Development Tools"

    export VSC_VERSION="${var.code_server_version}"
    wget https://github.com/coder/code-server/releases/download/v$VSC_VERSION/code-server-$VSC_VERSION-linux-amd64.tar.gz
    tar -xzf code-server-$VSC_VERSION-linux-amd64.tar.gz
    mv code-server-$VSC_VERSION-linux-amd64 /usr/local/lib/code-server
    ln -s /usr/local/lib/code-server/bin/code-server /usr/local/bin/code-server
    mkdir -p /home/ec2-user/.config/code-server
    cat <<EOF > /home/ec2-user/.config/code-server/config.yaml
    bind-addr: 0.0.0.0:8000
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
    systemctl enable code-server
    systemctl start code-server

    ${var.additional_user_data}
    # The marker is always the very last thing the script does. Touching it before
    # additional_user_data would let an SSM Association waiting on it start while kubectl and
    # helm are still installing (rules.md B-4/D-5).
    %{if var.marker_file_path != null~}
    mkdir -p ${var.marker_file_path}
    touch ${var.marker_file_path}/userdata
    %{endif~}
    EOT

  subnet_id                   = var.subnet_id
  associate_public_ip_address = true
  vpc_security_group_ids      = concat([aws_security_group.vscode_ec2_security_group.id], var.extra_security_group_ids)

  tags = {
    Name = "vscode"
  }

  depends_on = [aws_iam_role_policy_attachment.vscode_ec2_iam_role]
}
