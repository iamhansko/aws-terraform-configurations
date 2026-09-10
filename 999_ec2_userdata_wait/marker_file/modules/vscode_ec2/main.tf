variable "name" {
  type        = string
  default     = "vscode"
  description = "Name tag for the VS Code EC2 instance"
}

variable "instance_type" {
  type        = string
  default     = "t3.small"
  description = "EC2 instance type"
}

variable "ami_id" {
  type        = string
  description = "AMI ID to launch the instance from"
}

variable "key_name" {
  type        = string
  description = "EC2 key pair name to attach to the instance"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID where the security group is created"
}

variable "subnet_id" {
  type        = string
  description = "Subnet ID where the instance is launched"
}

variable "associate_public_ip_address" {
  type        = bool
  default     = true
  description = "Whether to associate a public IP address with the instance"
}

variable "marker_file_path" {
  type        = string
  default     = "/run/terraform"
  description = "Directory used to store userdata/command completion marker files"
}

resource "aws_iam_role_policy_attachment" "vscode_ec2_iam_role" {
  role       = aws_iam_role.vscode_ec2_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_instance" "vscode_ec2" {
  ami           = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name
  tags = {
    Name = var.name
  }
  iam_instance_profile        = aws_iam_instance_profile.vscode_ec2_instance_profile.name
  user_data                   = <<-EOT
    #!/bin/bash
    set -x
    dnf update -y
    dnf install -y git
    dnf groupinstall -y "Development Tools"
    dnf install -yq python3.13
    ln -sf /usr/bin/python3.13 /usr/bin/python
    python -m ensurepip --upgrade

    export VSC_VERSION="4.102.3"
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

    date > /home/ec2-user/BEFORE_MARK.md

    mkdir -p ${var.marker_file_path}
    touch ${var.marker_file_path}/userdata

    sleep 120
    date > /home/ec2-user/AFTER_MARK.md
    EOT
  subnet_id                   = var.subnet_id
  associate_public_ip_address = var.associate_public_ip_address
  vpc_security_group_ids      = [aws_security_group.vscode_ec2_security_group.id]
}

resource "aws_security_group" "vscode_ec2_security_group" {
  description = "Security Group for Bastion EC2 SSH Connection"
  name        = "bastion-sg"
  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 22
    protocol    = "tcp"
    to_port     = 22
  }
  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 8000
    protocol    = "tcp"
    to_port     = 8000
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  vpc_id = var.vpc_id
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

resource "aws_iam_instance_profile" "vscode_ec2_instance_profile" {
  role = aws_iam_role.vscode_ec2_iam_role.name
}
