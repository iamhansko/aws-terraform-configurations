data "aws_ssm_parameter" "ami_id" {
  name = var.ami_ssm_parameter_name
}

resource "aws_security_group" "web_ec2_security_group" {
  description = "Security Group"
  name        = "web-ec2-sg"
  vpc_id      = var.vpc_id

  # Iterating the map directly, not toset() over a list of IDs: the IDs come from
  # another module's security group and are unknown until apply, and a for_each -
  # in a dynamic block just as in a resource - needs keys it can determine during
  # plan. The caller's labels supply them (rules.md B-8).
  dynamic "ingress" {
    for_each = var.ingress_source_security_groups
    content {
      description     = "Port 80 from the ${ingress.key} security group"
      protocol        = "tcp"
      from_port       = 80
      to_port         = 80
      security_groups = [ingress.value]
    }
  }

  tags = {
    Name = "web-ec2-sg"
  }
}

resource "aws_vpc_security_group_egress_rule" "security_group_egress" {
  security_group_id = aws_security_group.web_ec2_security_group.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_instance" "web_ec2" {
  ami           = data.aws_ssm_parameter.ami_id.insecure_value
  instance_type = var.instance_type
  key_name      = var.key_name

  user_data = <<-EOT
    #!/bin/bash
    dnf update -yq
    dnf install -yq docker
    systemctl enable --now docker
    usermod -aG docker ec2-user
    newgrp docker
    docker run -d -p 80:80 --restart always nginx
    EOT

  subnet_id                   = var.subnet_id
  associate_public_ip_address = false
  vpc_security_group_ids      = [aws_security_group.web_ec2_security_group.id]

  tags = {
    Name = "web"
  }
}
