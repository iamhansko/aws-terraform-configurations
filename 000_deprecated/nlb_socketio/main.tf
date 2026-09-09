# Generated from 000_deprecated/nlb_socketio.yaml by tools/cfn2tf.
# CloudFormation stack -> Terraform root module.
terraform {
  required_version = ">= 1.5"
  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 6.0" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
    tls    = { source = "hashicorp/tls", version = "~> 4.0" }
  }
}
provider "aws" {
  region = var.aws_region
}
variable "aws_region" {
  type        = string
  default     = null
  description = "Target AWS region. Defaults to the provider chain (AWS_REGION)."
}
variable "stack_name" {
  type        = string
  default     = "nlb-socketio"
  description = "Stands in for AWS::StackName."
}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}
# Provides the unique suffix that AWS::StackId supplies in CloudFormation.
resource "random_uuid" "stack_id" {}
# --- Mappings / Conditions ---
locals {
  mappings = {
    RegionMap = {
      "us-east-1" = {
        AmazonLinux2023 = "ami-0182f373e66f89c85"
      }
      "ap-northeast-2" = {
        AmazonLinux2023 = "ami-0023481579962abd4"
      }
    }
  }
  stack_id = "arn:${data.aws_partition.current.partition}:cloudformation:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:stack/${var.stack_name}/${random_uuid.stack_id.result}"
}
# --- Resources split out of composite CloudFormation resources ---
resource "tls_private_key" "key_pair" {
  algorithm = "RSA"
  rsa_bits  = 4096
}
# CloudFormation stores the generated private key in SSM at /ec2/keypair/<key-pair-id>; mirrored below.
resource "aws_ssm_parameter" "key_pair_private_key" {
  name  = "/ec2/keypair/${aws_key_pair.key_pair.key_pair_id}"
  type  = "SecureString"
  value = tls_private_key.key_pair.private_key_pem
}
resource "aws_iam_role_policy_attachment" "bastion_ec2_iam_role" {
  role       = aws_iam_role.bastion_ec2_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}
# --- Resources ---
resource "aws_key_pair" "key_pair" {
  key_name   = "key-${element(split("-", element(split("/", local.stack_id), 2)), 3)}"
  public_key = tls_private_key.key_pair.public_key_openssh
}
resource "aws_vpc" "vpc" {
  cidr_block = "10.1.0.0/16"
  tags = {
    Name = "stem-vpc"
  }
}
resource "aws_subnet" "public_subnet_a" {
  availability_zone = "${data.aws_region.current.region}a"
  cidr_block        = "10.1.2.0/24"
  tags = {
    Name = "stem-public-a"
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_subnet" "public_subnet_b" {
  availability_zone = "${data.aws_region.current.region}b"
  cidr_block        = "10.1.3.0/24"
  tags = {
    Name = "stem-public-b"
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_subnet" "private_subnet_a" {
  availability_zone = "${data.aws_region.current.region}a"
  cidr_block        = "10.1.0.0/24"
  tags = {
    Name = "stem-private-a"
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_subnet" "private_subnet_b" {
  availability_zone = "${data.aws_region.current.region}b"
  cidr_block        = "10.1.1.0/24"
  tags = {
    Name = "stem-private-b"
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_internet_gateway" "internet_gateway" {
  tags = {
    Name = "stem-igw"
  }
}
resource "aws_internet_gateway_attachment" "vpc_internet_gateway_attachment" {
  internet_gateway_id = aws_internet_gateway.internet_gateway.id
  vpc_id              = aws_vpc.vpc.id
}
resource "aws_eip" "nat_gateway_a_elastic_ip" {}
resource "aws_nat_gateway" "nat_gateway_a" {
  allocation_id = aws_eip.nat_gateway_a_elastic_ip.allocation_id
  subnet_id     = aws_subnet.public_subnet_a.id
  tags = {
    Name = "stem-natgw-a"
  }
}
resource "aws_eip" "nat_gateway_b_elastic_ip" {}
resource "aws_nat_gateway" "nat_gateway_b" {
  allocation_id = aws_eip.nat_gateway_b_elastic_ip.allocation_id
  subnet_id     = aws_subnet.public_subnet_b.id
  tags = {
    Name = "stem-natgw-b"
  }
}
resource "aws_route_table" "public_subnet_route_table" {
  tags = {
    Name = "stem-public-rt"
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_route" "public_subnet_route" {
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.internet_gateway.id
  route_table_id         = aws_route_table.public_subnet_route_table.id
}
resource "aws_route_table_association" "public_subnet_a_route_table_association" {
  route_table_id = aws_route_table.public_subnet_route_table.id
  subnet_id      = aws_subnet.public_subnet_a.id
}
resource "aws_route_table_association" "public_subnet_b_route_table_association" {
  route_table_id = aws_route_table.public_subnet_route_table.id
  subnet_id      = aws_subnet.public_subnet_b.id
}
resource "aws_route_table" "private_subnet_a_route_table" {
  tags = {
    Name = "stem-private-a-rt"
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_route_table_association" "private_subnet_a_route_table_association" {
  route_table_id = aws_route_table.private_subnet_a_route_table.id
  subnet_id      = aws_subnet.private_subnet_a.id
}
resource "aws_route" "private_subnet_a_route" {
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gateway_a.id
  route_table_id         = aws_route_table.private_subnet_a_route_table.id
}
resource "aws_route_table" "private_subnet_b_route_table" {
  tags = {
    Name = "stem-private-b-rt"
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_route_table_association" "private_subnet_b_route_table_association" {
  route_table_id = aws_route_table.private_subnet_b_route_table.id
  subnet_id      = aws_subnet.private_subnet_b.id
}
resource "aws_route" "private_subnet_b_route" {
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gateway_b.id
  route_table_id         = aws_route_table.private_subnet_b_route_table.id
}
resource "aws_instance" "bastion_ec2" {
  ami           = local.mappings["RegionMap"][data.aws_region.current.region]["AmazonLinux2023"]
  instance_type = "t3.small"
  key_name      = aws_key_pair.key_pair.key_name
  tags = {
    Name = "stem-bastion-ec2"
  }
  iam_instance_profile        = aws_iam_instance_profile.bastion_ec2_instance_profile.name
  subnet_id                   = aws_subnet.public_subnet_a.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.bastion_ec2_security_group.id]
}
resource "aws_security_group" "bastion_ec2_security_group" {
  description = "Security Group for Bastion EC2 SSH Connection"
  name        = "bastion-sg"
  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 22
    protocol    = "tcp"
    to_port     = 22
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_iam_role" "bastion_ec2_iam_role" {
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
  name = "Ec2PowerUserRole"
}
resource "aws_iam_instance_profile" "bastion_ec2_instance_profile" {
  name = "Ec2PowerUserProfile"
  role = jsonencode([aws_iam_role.bastion_ec2_iam_role.name])
}
resource "aws_launch_template" "launch_template" {
  name          = "stem-template"
  image_id      = local.mappings["RegionMap"][data.aws_region.current.region]["AmazonLinux2023"]
  instance_type = "t3.small"
  key_name      = aws_key_pair.key_pair.key_name
  network_interfaces {
    device_index    = 0
    security_groups = [aws_security_group.auto_scaling_group_security_group.id]
  }
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "stem-asg"
    }
  }
  user_data = base64encode(<<EOT
#!/bin/bash
su - ec2-user <<'EOF'
sudo dnf update -y
sudo dnf install -y git
cd /home/ec2-user
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.0/install.sh | bash
export NVM_DIR="/home/ec2-user/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
nvm install 18
git clone https://github.com/jeanrauwers/node-multiplayer.git
cd /home/ec2-user/node-multiplayer
export NODE_OPTIONS=--openssl-legacy-provider
npm install
npm run start:game
EOF
EOT
  )
}
resource "aws_autoscaling_group" "auto_scaling_group" {
  name               = "stem-asg"
  availability_zones = ["${data.aws_region.current.region}a", "${data.aws_region.current.region}b"]
  launch_template {
    id      = aws_launch_template.launch_template.id
    version = aws_launch_template.launch_template.latest_version
  }
  max_size            = 4
  min_size            = 2
  target_group_arns   = [aws_lb_target_group.target_group.arn]
  vpc_zone_identifier = [aws_subnet.private_subnet_a.id, aws_subnet.private_subnet_b.id]
}
resource "aws_autoscaling_policy" "auto_scaling_policy" {
  adjustment_type        = "PercentChangeInCapacity"
  autoscaling_group_name = aws_autoscaling_group.auto_scaling_group.name
  policy_type            = "TargetTrackingScaling"
  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 30
  }
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  name = "${var.stack_name}-auto-scaling-policy"
}
resource "aws_security_group" "auto_scaling_group_security_group" {
  description = "Security Group for AutoScalingGroup EC2"
  name        = "asg-sg"
  ingress {
    from_port       = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_ec2_security_group.id]
    to_port         = 22
  }
  ingress {
    from_port       = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_ec2_security_group.id]
    to_port         = 3000
  }
  ingress {
    from_port       = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.network_load_balancer_security_group.id]
    to_port         = 3000
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_lb" "network_load_balancer" {
  ip_address_type    = "ipv4"
  name               = "stem-nlb"
  security_groups    = [aws_security_group.network_load_balancer_security_group.id]
  subnets            = [aws_subnet.public_subnet_a.id, aws_subnet.public_subnet_b.id]
  load_balancer_type = "network"
  internal           = false
}
resource "aws_security_group" "network_load_balancer_security_group" {
  description = "Security Group for Network Load Balancer"
  name        = "nlb-sg"
  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 80
    protocol    = "tcp"
    to_port     = 80
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_lb_listener" "listener" {
  default_action {
    target_group_arn = aws_lb_target_group.target_group.arn
    type             = "forward"
  }
  load_balancer_arn = aws_lb.network_load_balancer.arn
  port              = 80
  protocol          = "TCP"
}
resource "aws_lb_target_group" "target_group" {
  ip_address_type = "ipv4"
  name            = "stem-tg"
  port            = 3000
  protocol        = "TCP"
  target_type     = "instance"
  vpc_id          = aws_vpc.vpc.id
  health_check {
    protocol            = "TCP"
    interval            = 60
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    enabled             = true
  }
}
