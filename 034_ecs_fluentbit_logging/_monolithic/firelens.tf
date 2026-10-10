# Generated from 034_ecs_fluentbit_logging/firelens.yaml by tools/cfn2tf.
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
  default     = "firelens"
  description = "Stands in for AWS::StackName."
}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}
# Provides the unique suffix that AWS::StackId supplies in CloudFormation.
resource "random_uuid" "stack_id" {}
# --- Parameters ---
variable "bastion_ec2_ami_id" {
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
  description = "(SSM parameter path; resolved by the aws_ssm_parameter data source)"
}
data "aws_ssm_parameter" "bastion_ec2_ami_id" {
  name = var.bastion_ec2_ami_id
}
variable "ecs_ami_id" {
  type        = string
  default     = "/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id"
  description = "(SSM parameter path; resolved by the aws_ssm_parameter data source)"
}
data "aws_ssm_parameter" "ecs_ami_id" {
  name = var.ecs_ami_id
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
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
resource "aws_iam_role_policy_attachment" "ecs_container_instance_iam_role_0" {
  role       = aws_iam_role.ecs_container_instance_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}
resource "aws_iam_role_policy_attachment" "ecs_container_instance_iam_role_1" {
  role       = aws_iam_role.ecs_container_instance_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
resource "aws_iam_role_policy_attachment" "ecs_task_role" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchFullAccessV2"
}
resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_0" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_1" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchFullAccessV2"
}
# --- Resources ---
resource "aws_key_pair" "key_pair" {
  key_name   = "key-${local.stack_suffix}"
  public_key = tls_private_key.key_pair.public_key_openssh
}
resource "aws_vpc" "vpc" {
  cidr_block           = "10.101.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "logging-vpc"
  }
}
resource "aws_subnet" "public_subnet_a" {
  vpc_id                  = aws_vpc.vpc.id
  availability_zone       = "${data.aws_region.current.region}a"
  cidr_block              = element([for __i in range(4) : cidrsubnet(aws_vpc.vpc.cidr_block, 32 - 8 - tonumber(split("/", aws_vpc.vpc.cidr_block)[1]), __i)], 0)
  map_public_ip_on_launch = true
  tags = {
    Name = "logging-pub-a"
  }
}
resource "aws_subnet" "public_subnet_b" {
  vpc_id                  = aws_vpc.vpc.id
  availability_zone       = "${data.aws_region.current.region}b"
  cidr_block              = element([for __i in range(4) : cidrsubnet(aws_vpc.vpc.cidr_block, 32 - 8 - tonumber(split("/", aws_vpc.vpc.cidr_block)[1]), __i)], 1)
  map_public_ip_on_launch = true
  tags = {
    Name = "logging-pub-b"
  }
}
resource "aws_internet_gateway" "igw" {
  tags = {
    Name = "logging-igw"
  }
}
resource "aws_internet_gateway_attachment" "igw_attachment" {
  vpc_id              = aws_vpc.vpc.id
  internet_gateway_id = aws_internet_gateway.igw.id
}
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "logging-pub-rt"
  }
}
resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}
resource "aws_route_table_association" "public_subnet_a_route_table" {
  subnet_id      = aws_subnet.public_subnet_a.id
  route_table_id = aws_route_table.public_route_table.id
}
resource "aws_route_table_association" "public_subnet_b_route_table" {
  subnet_id      = aws_subnet.public_subnet_b.id
  route_table_id = aws_route_table.public_route_table.id
}
# CreationPolicy: CloudFormation CreationPolicy (cfn-signal) has no Terraform equivalent; the wait is not reproduced.
# # {
# #   "ResourceSignal": {
# #     "Count": "1",
# #     "Timeout": "PT7M"
# #   }
# # }
resource "aws_instance" "bastion_ec2" {
  instance_type        = "t3.micro"
  ami                  = data.aws_ssm_parameter.bastion_ec2_ami_id.insecure_value
  key_name             = aws_key_pair.key_pair.key_name
  iam_instance_profile = aws_iam_instance_profile.bastion_ec2_instance_profile.name
  tags = {
    Name = "logging-bastion"
  }
  user_data                   = <<EOT
#!/bin/bash
dnf update -yq
dnf groupinstall -yq "Development Tools"
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

/opt/aws/bin/cfn-signal -e $? --stack ${var.stack_name} --resource BastionEc2 --region ${data.aws_region.current.region}
EOT
  subnet_id                   = aws_subnet.public_subnet_a.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.bastion_ec2_security_group.id]
}
resource "aws_security_group" "bastion_ec2_security_group" {
  vpc_id      = aws_vpc.vpc.id
  description = "Security Group"
  ingress {
    protocol    = "tcp"
    from_port   = 22
    to_port     = 22
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    protocol    = "tcp"
    from_port   = 8000
    to_port     = 8000
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "bastion-ec2-sg"
  }
}
resource "aws_iam_role" "bastion_ec2_iam_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}
resource "aws_iam_instance_profile" "bastion_ec2_instance_profile" {
  # An instance profile holds at most one role, so this attribute is a single
  # role name string - not the list CloudFormation's AWS::IAM::InstanceProfile
  # Roles property takes. jsonencode([...]) here sends the literal string
  # ["terraform-..."] as roleName, which IAM rejects with a ValidationError
  # during apply, while terraform validate and plan both pass because the
  # attribute is a string either way (rules.md A-3).
  role = aws_iam_role.bastion_ec2_iam_role.name
}
resource "aws_eip" "bastion_elastic_ip" {}
resource "aws_eip_association" "bastion_elastic_ip_association" {
  allocation_id = aws_eip.bastion_elastic_ip.allocation_id
  instance_id   = aws_instance.bastion_ec2.id
}
resource "aws_ecr_repository" "app_ecr" {
  name = "logging-ecr"
  image_scanning_configuration {
    scan_on_push = true
  }
  encryption_configuration {
    encryption_type = "AES256"
  }
  image_tag_mutability = "IMMUTABLE"
}
resource "aws_ecr_repository" "fluentbit_ecr" {
  name = "logging-fluentbit"
  image_scanning_configuration {
    scan_on_push = true
  }
  encryption_configuration {
    encryption_type = "AES256"
  }
  image_tag_mutability = "IMMUTABLE"
}
resource "aws_ssm_association" "ecr_ssm_association" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = 900
  targets {
    key    = "InstanceIds"
    values = [aws_instance.bastion_ec2.id]
  }
  parameters = {
    commands = join("\n", ["dnf install -yq docker\nsystemctl start docker\nsystemctl enable docker\n# usermod -aG docker ec2-user\n# newgrp docker\nchmod 666 /var/run/docker.sock\n\nsu - ec2-user << EOF\ncd /home/ec2-user\necho '#!/usr/bin/env python3\n\nimport time\nimport json\nimport random\nfrom datetime import datetime\n\nLOG_LEVELS = [\"INFO\", \"DEBUG\", \"WARNING\", \"ERROR\", \"CRITICAL\"]\n\nMESSAGES = {\n    \"INFO\": \"Service started successfully.\",\n    \"DEBUG\": \"Debugging variable state.\",\n    \"WARNING\": \"Memory usage nearing limit.\",\n    \"ERROR\": \"Unable to connect to database.\",\n    \"CRITICAL\": \"System failure! Immediate action required.\"\n}\n\ndef generate_token():\n    return \"\".join(random.choices(\"abcdefghijklmnopqrstuvwxyz0123456789\", k=16))\n\ndef generate_log():\n    while True:\n        log_level = random.choice(LOG_LEVELS)\n        log_entry = {\n            \"timestamp\": datetime.utcnow().isoformat() + \"Z\",\n            \"log_level\": log_level,\n            \"message\": MESSAGES[log_level]\n        }\n\n        if log_level == \"ERROR\":\n            log_entry[\"token\"] = generate_token()\n\n        print(json.dumps(log_entry))\n        time.sleep(random.uniform(0.5, 2.0))\n\nif __name__ == \"__main__\":\n    generate_log()' > log_generator.py\n\naws ecr get-login-password --region ${data.aws_region.current.region} | docker login --username AWS --password-stdin ${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.region}.amazonaws.com\n\necho 'FROM python:3.13-slim\nWORKDIR /app\nCOPY log_generator.py .\nCMD [\"python\", \"log_generator.py\"]' > Dockerfile.app\ndocker build -f Dockerfile.app -t ${aws_ecr_repository.app_ecr.repository_url}:v1.0.0 .\ndocker push ${aws_ecr_repository.app_ecr.repository_url}:v1.0.0\n\necho 'FROM public.ecr.aws/aws-observability/aws-for-fluent-bit:latest' > Dockerfile.fluentbit\ndocker build -f Dockerfile.fluentbit -t ${aws_ecr_repository.fluentbit_ecr.repository_url}:v1.0.0 .\ndocker push ${aws_ecr_repository.fluentbit_ecr.repository_url}:v1.0.0\nEOF\n"])
  }
}
resource "aws_ecs_cluster" "ecs_cluster" {
  name = "logging-cluster"
}
resource "aws_ecs_capacity_provider" "ecs_ec2_capacity_provider" {
  auto_scaling_group_provider {
    auto_scaling_group_arn = aws_autoscaling_group.ecs_asg.arn
  }
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  name = "${var.stack_name}-ecs-ec2-capacity-provider"
}
resource "aws_ecs_cluster_capacity_providers" "ecs_ec2_capacity_provider_association" {
  capacity_providers = [aws_ecs_capacity_provider.ecs_ec2_capacity_provider.id]
  cluster_name       = aws_ecs_cluster.ecs_cluster.name
  default_capacity_provider_strategy {
    base              = 0
    capacity_provider = aws_ecs_capacity_provider.ecs_ec2_capacity_provider.id
    weight            = 100
  }
}
resource "aws_autoscaling_group" "ecs_asg" {
  min_size            = 1
  desired_capacity    = 1
  max_size            = 1
  vpc_zone_identifier = [aws_subnet.public_subnet_a.id, aws_subnet.public_subnet_b.id]
  launch_template {
    id      = aws_launch_template.ecs_lt.id
    version = aws_launch_template.ecs_lt.latest_version
  }
  depends_on = [aws_ecs_cluster.ecs_cluster]
}
resource "aws_launch_template" "ecs_lt" {
  image_id      = data.aws_ssm_parameter.ecs_ami_id.insecure_value
  instance_type = "t3.medium"
  iam_instance_profile {
    name = aws_iam_instance_profile.ecs_container_instance_profile.name
  }
  network_interfaces {
    device_index                = 0
    associate_public_ip_address = true
    security_groups             = [aws_security_group.ecs_container_instance_security_group.id]
  }
  user_data = base64encode(<<EOT
#!/bin/bash -xe
echo ECS_CLUSTER=${aws_ecs_cluster.ecs_cluster.name} >> /etc/ecs/ecs.config
dnf install -y aws-cfn-bootstrap
EOT
  )
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }
  key_name = aws_key_pair.key_pair.key_name
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "ecs-container-instance"
    }
  }
}
resource "aws_security_group" "ecs_container_instance_security_group" {
  description = "Security Group"
  name        = "ecs-container-instance-sg"
  ingress {
    protocol        = -1
    security_groups = [aws_vpc.vpc.default_security_group_id]
    from_port       = 0
    to_port         = 0
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_iam_role" "ecs_container_instance_iam_role" {
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
resource "aws_iam_instance_profile" "ecs_container_instance_profile" {
  name = "ContainerInstanceProfile-${local.stack_suffix}"
  # Single role name string, not a list (rules.md A-3).
  role = aws_iam_role.ecs_container_instance_iam_role.name
}
resource "aws_ecs_task_definition" "ecs_task_definition" {
  family = "logging-ecs-td"
  cpu    = "512"
  memory = "1024"
  container_definitions = jsonencode([{
    Name      = "app-logger"
    Image     = "${aws_ecr_repository.app_ecr.repository_url}:v1.0.0"
    Essential = true
    LogConfiguration = {
      LogDriver = "awsfirelens"
      Options = {
        Name              = "cloudwatch_logs"
        log_group_name    = "/logging/cloudwatch"
        auto_create_group = "true"
        log_stream_prefix = "app-"
        region            = data.aws_region.current.region
      }
    }
    }, {
    Name  = "log-router"
    Image = "${aws_ecr_repository.fluentbit_ecr.repository_url}:v1.0.0"
    FirelensConfiguration = {
      Type = "fluentbit"
    }
    Essential = true
    LogConfiguration = {
      LogDriver = "awslogs"
      Options = {
        "awslogs-group"        = "/fluentbit/cloudwatch"
        "awslogs-create-group" = "true"
        "awslogs-region"       = data.aws_region.current.region
      }
    }
    Environment = [{
      Name  = "FLB_LOG_LEVEL"
      Value = "error"
    }]
  }])
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]
  runtime_platform {
    cpu_architecture        = "X86_64"
    operating_system_family = "LINUX"
  }
  task_role_arn      = aws_iam_role.ecs_task_role.arn
  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn
  depends_on         = [aws_ssm_association.ecr_ssm_association]
}
resource "aws_iam_role" "ecs_task_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}
resource "aws_iam_role" "ecs_task_execution_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}
resource "aws_ecs_service" "ecs_service" {
  name            = "logging-svc"
  cluster         = aws_ecs_cluster.ecs_cluster.name
  task_definition = aws_ecs_task_definition.ecs_task_definition.arn
  desired_count   = 2
  launch_type     = "EC2"
}
resource "aws_security_group" "ecs_service_security_group" {
  description = "Security Group"
  name        = "ecs-service-sg"
  ingress {
    protocol        = -1
    security_groups = [aws_vpc.vpc.default_security_group_id]
    from_port       = 0
    to_port         = 0
  }
  vpc_id = aws_vpc.vpc.id
}
# --- Outputs ---
# CloudFormation output: VsCode
output "vs_code" {
  # public_ip, not id. CloudFormation's Ref on an AWS::EC2::EIP returns the IP
  # address, but aws_eip.id is the allocation ID, so the conversion's blanket
  # Ref -> .id mapping produced http://eipalloc-...:8000 here. The allocation ID
  # is what Fn::GetAtt AllocationId returns, which this template never asked for.
  value       = "http://${aws_eip.bastion_elastic_ip.public_ip}:8000"
  description = "VsCode on BastionEC2"
}
