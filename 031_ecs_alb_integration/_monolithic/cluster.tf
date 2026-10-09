# Generated from 031_ecs_alb_integration/cluster.yaml by tools/cfn2tf.
# CloudFormation stack -> Terraform root module.
terraform {
  required_version = ">= 1.9"
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
  default     = "cluster"
  description = "Stands in for AWS::StackName."
}
data "aws_availability_zones" "available" {}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}
# Provides the unique suffix that AWS::StackId supplies in CloudFormation.
resource "random_uuid" "stack_id" {}
# --- Parameters ---
variable "vpc_cidr" {
  type    = string
  default = "10.10.0.0/16"
}
variable "subnet_a_cidr" {
  type    = string
  default = "10.10.0.0/24"
}
variable "subnet_c_cidr" {
  type    = string
  default = "10.10.1.0/24"
}
variable "bastion_ec2_ami_id" {
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
  description = "(SSM parameter path; resolved by the aws_ssm_parameter data source)"
}
data "aws_ssm_parameter" "bastion_ec2_ami_id" {
  name = var.bastion_ec2_ami_id
}
# --- Mappings / Conditions ---
locals {
  stack_id = "arn:${data.aws_partition.current.partition}:cloudformation:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:stack/${var.stack_name}/${random_uuid.stack_id.result}"
  # Unique per deployment, taken from the generated stack id - the same group aws_key_pair already used for
  # its name. Appended below to every name whose namespace is account-wide rather than per-VPC, so that two
  # of these projects, or two copies of this one, can exist in one account. Several of these literals were
  # shared by four projects at once (rules.md G-3).
  stack_suffix = element(split("-", element(split("/", local.stack_id), 2)), 3)
}
# --- Resources split out of composite CloudFormation resources ---
resource "aws_iam_role_policy_attachment" "ecs_task_execution_role" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
resource "aws_iam_role_policy_attachment" "bastion_ec2_iam_role" {
  role       = aws_iam_role.bastion_ec2_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
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
# --- Resources ---
resource "aws_vpc" "vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "mo-vpc"
  }
}
resource "aws_internet_gateway" "igw" {
  tags = {
    Name = "mo-igw"
  }
}
resource "aws_internet_gateway_attachment" "igw_attachment" {
  vpc_id              = aws_vpc.vpc.id
  internet_gateway_id = aws_internet_gateway.igw.id
}
resource "aws_subnet" "public_subnet_a" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = var.subnet_a_cidr
  availability_zone       = element(data.aws_availability_zones.available.names, 0)
  map_public_ip_on_launch = true
  tags = {
    Name = "mo-public-a"
  }
}
resource "aws_subnet" "public_subnet_c" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = var.subnet_c_cidr
  availability_zone       = element(data.aws_availability_zones.available.names, 2)
  map_public_ip_on_launch = true
  tags = {
    Name = "mo-public-c"
  }
}
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "mo-rt"
  }
}
resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}
resource "aws_route_table_association" "public_subnet_a_rt_association" {
  subnet_id      = aws_subnet.public_subnet_a.id
  route_table_id = aws_route_table.public_rt.id
}
resource "aws_route_table_association" "public_subnet_c_rt_association" {
  subnet_id      = aws_subnet.public_subnet_c.id
  route_table_id = aws_route_table.public_rt.id
}
resource "aws_ecs_cluster" "ecs_cluster" {
  name = "ecs-cluster"
}
resource "aws_ecr_repository" "ecr" {
  name         = "monitoring"
  force_delete = true
}
resource "aws_ecs_task_definition" "ecs_task_definition" {
  family                   = "monitoring-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  container_definitions = jsonencode([{
    Name  = "monitoring"
    Image = "${aws_ecr_repository.ecr.repository_url}:latest"
    PortMappings = [{
      ContainerPort = 80
    }]
    Essential = true
  }])
}
resource "aws_iam_role" "ecs_task_execution_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["ecs-tasks.amazonaws.com"]
      }
      Action = ["sts:AssumeRole"]
    }]
  })
}
resource "aws_lb" "alb" {
  name               = "mo-alb"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_security_group.id]
  subnets            = [aws_subnet.public_subnet_a.id, aws_subnet.public_subnet_c.id]
  internal           = false
}
resource "aws_security_group" "alb_security_group" {
  vpc_id      = aws_vpc.vpc.id
  description = "Security Group"
  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "alb-sg"
  }
}
resource "aws_lb_listener" "alb_listener" {
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb_target_group.arn
  }
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"
}
resource "aws_lb_target_group" "alb_target_group" {
  name        = "mo-tg"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.vpc.id
  health_check {
    path     = "/"
    protocol = "HTTP"
    port     = 80
  }
}
resource "aws_ecs_service" "ecs_service" {
  name            = "monitoring-svc"
  cluster         = aws_ecs_cluster.ecs_cluster.name
  task_definition = aws_ecs_task_definition.ecs_task_definition.arn
  launch_type     = "FARGATE"
  desired_count   = 1
  network_configuration {
    assign_public_ip = true
    security_groups  = [aws_security_group.ecs_service_security_group.id]
    subnets          = [aws_subnet.public_subnet_a.id, aws_subnet.public_subnet_c.id]
  }
  load_balancer {
    container_name   = "monitoring"
    container_port   = 80
    target_group_arn = aws_lb_target_group.alb_target_group.arn
  }
  depends_on = [aws_lb.alb, aws_lb_listener.alb_listener]
}
resource "aws_security_group" "ecs_service_security_group" {
  vpc_id      = aws_vpc.vpc.id
  description = "Security Group"
  ingress {
    protocol        = "tcp"
    from_port       = 80
    to_port         = 80
    security_groups = [aws_security_group.alb_security_group.id]
  }
  tags = {
    Name = "ecs-svc-sg"
  }
}
resource "aws_cloudwatch_dashboard" "cloud_watchg_dashboard" {
  dashboard_name = "monitoring-dashboard"
  dashboard_body = <<EOT
{
  "widgets": [
    {
      "type": "metric",
      "x": 0, "y": 0, "width": 8, "height": 7,
      "properties": {
        "metrics": [
          [ "AWS/ECS", "CPUUtilization", "ClusterName", "${aws_ecs_cluster.ecs_cluster.name}", "ServiceName", "${aws_ecs_service.ecs_service.name}" ],
          [ ".", "MemoryUtilization", ".", ".", ".", "." ]
        ],
        "period": 60,
        "stat": "Average",
        "title": "ECS CPU/Memory Usage",
        "region": "${data.aws_region.current.region}"
      }
    },
    {
      "type": "metric",
      "x": 8, "y": 0, "width": 8, "height": 7,
      "properties": {
        "metrics": [
          [ "AWS/ApplicationELB", "RequestCount", "LoadBalancer", "${aws_lb.alb.arn_suffix}" ],
          [ ".", "HTTPCode_Target_5XX_Count", ".", "." ]
        ],
        "period": 60,
        "stat": "Sum",
        "title": "ALB Requests & 5xx Errors",
        "region": "${data.aws_region.current.region}"
      }
    }
  ]
}
EOT
}
resource "aws_cloudwatch_metric_alarm" "cloud_watch_alarm" {
  alarm_name          = "alb-5xx-alarm"
  alarm_description   = "5xx 에러가 2번 이상 발생했습니다."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  dimensions          = {}
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 2
  comparison_operator = "GreaterThanOrEqualToThreshold"
  actions_enabled     = true
  treat_missing_data  = "notBreaching"
}
# CreationPolicy: CloudFormation CreationPolicy (cfn-signal) has no Terraform equivalent; the wait is not reproduced.
# # {
# #   "ResourceSignal": {
# #     "Count": "1",
# #     "Timeout": "PT7M"
# #   }
# # }
resource "aws_instance" "bastion_ec2" {
  iam_instance_profile = aws_iam_instance_profile.bastion_ec2_instance_profile.name
  ami                  = data.aws_ssm_parameter.bastion_ec2_ami_id.insecure_value
  instance_type        = "t3.small"
  key_name             = aws_key_pair.key_pair.key_name
  tags = {
    Name = "bastion"
  }
  user_data                   = <<EOT
#!/bin/bash
dnf update -y
dnf groupinstall -y "Development Tools"
dnf install -y python3.12
dnf install -y python3-pip
ln -s /usr/bin/python3.12 /usr/bin/python

dnf install -y git

wget https://github.com/coder/code-server/releases/download/v4.100.3/code-server-4.100.3-linux-amd64.tar.gz
tar -xzf code-server-4.100.3-linux-amd64.tar.gz
mv code-server-4.100.3-linux-amd64 /usr/local/lib/code-server
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

dnf install -yq docker
systemctl start docker
systemctl enable docker
# usermod -aG docker ec2-user
# newgrp docker
chmod 666 /var/run/docker.sock

su - ec2-user << EOF
cd /home/ec2-user
aws ecr get-login-password --region ${data.aws_region.current.region} | docker login --username AWS --password-stdin ${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.region}.amazonaws.com
echo 'from flask import Flask
app = Flask(__name__)

@app.route("/")
def index():
  return "Hello ECS"

@app.route("/health")
def healthcheck():
  return "Healthy"

@app.route("/error")
def error():
  return "Server Error", 500

if __name__ == "__main__":
  app.run(host="0.0.0.0", port=80)' > monitoring.py
echo 'FROM python:3.13-slim
WORKDIR /app
COPY monitoring.py .
RUN pip install --no-cache-dir Flask
CMD ["python", "monitoring.py"]' > Dockerfile
docker build -t ${aws_ecr_repository.ecr.repository_url} .
docker push ${aws_ecr_repository.ecr.repository_url}
EOF

/opt/aws/bin/cfn-signal -e $? --stack ${var.stack_name} --resource BastionEc2 --region ${data.aws_region.current.region}
EOT
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
  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 8000
    protocol    = "tcp"
    to_port     = 8000
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
}
resource "aws_iam_instance_profile" "bastion_ec2_instance_profile" {
  name = "Ec2AdminProfile-${local.stack_suffix}"
  # An instance profile holds at most one role, so this attribute is a single
  # role name string - not the list CloudFormation's AWS::IAM::InstanceProfile
  # Roles property takes. jsonencode([...]) here sends the literal string
  # ["terraform-..."] as roleName, which IAM rejects with a ValidationError
  # during apply, while terraform validate and plan both pass because the
  # attribute is a string either way (rules.md A-3).
  role = aws_iam_role.bastion_ec2_iam_role.name
}
resource "aws_key_pair" "key_pair" {
  key_name   = "key-${local.stack_suffix}"
  public_key = tls_private_key.key_pair.public_key_openssh
}
