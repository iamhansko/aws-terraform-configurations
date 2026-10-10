# Generated from 085_ecs_service_connect/cluster.yaml by tools/cfn2tf.
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
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}
# Provides the unique suffix that AWS::StackId supplies in CloudFormation.
resource "random_uuid" "stack_id" {}
# --- Parameters ---
variable "inbound_from_anywhere" {
  type        = string
  default     = "True"
  description = "SecurityGroup Inbound Rule (Source 0.0.0.0/0)"
  validation {
    condition     = contains(["True", "False"], var.inbound_from_anywhere)
    error_message = "InboundFromAnywhere must be one of: True, False"
  }
}
variable "ami_id" {
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
  description = "(SSM parameter path; resolved by the aws_ssm_parameter data source)"
}
data "aws_ssm_parameter" "ami_id" {
  name = var.ami_id
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
  mappings = {
    AzMapping = {
      a = {
        PublicSubnetCidr  = "10.0.0.0/24"
        PrivateSubnetCidr = "10.0.1.0/24"
      }
      b = {
        PublicSubnetCidr  = "10.0.2.0/24"
        PrivateSubnetCidr = "10.0.3.0/24"
      }
      c = {
        PublicSubnetCidr  = "10.0.4.0/24"
        PrivateSubnetCidr = "10.0.5.0/24"
      }
    }
  }
  stack_id = "arn:${data.aws_partition.current.partition}:cloudformation:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:stack/${var.stack_name}/${random_uuid.stack_id.result}"
  # Unique per deployment, taken from the generated stack id - the same group aws_key_pair already used for
  # its name. Appended below to every name whose namespace is account-wide rather than per-VPC, so that two
  # of these projects, or two copies of this one, can exist in one account. Several of these literals were
  # shared by four projects at once (rules.md G-3).
  stack_suffix                              = element(split("-", element(split("/", local.stack_id), 2)), 3)
  cond_security_group_inbound_from_anywhere = (var.inbound_from_anywhere == "True")
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
resource "aws_iam_role_policy_attachment" "vs_code_ec2_iam_role" {
  role       = aws_iam_role.vs_code_ec2_iam_role.name
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
resource "aws_iam_role_policy" "ecs_task_role" {
  name = "EcsExecPolicy"
  role = aws_iam_role.ecs_task_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ssmmessages:CreateControlChannel", "ssmmessages:CreateDataChannel", "ssmmessages:OpenControlChannel", "ssmmessages:OpenDataChannel"]
      Resource = "*"
    }]
  })
}
resource "aws_iam_role_policy_attachment" "ecs_task_role" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}
resource "aws_iam_role_policy_attachment" "ecs_task_execution_role" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
# --- Resources ---
resource "aws_key_pair" "key_pair" {
  key_name   = "key-${local.stack_suffix}"
  public_key = tls_private_key.key_pair.public_key_openssh
}
resource "aws_vpc" "vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "vpc"
  }
}
resource "aws_internet_gateway" "internet_gateway" {
  tags = {
    Name = "igw"
  }
}
resource "aws_internet_gateway_attachment" "vpc_internet_gateway_attachment" {
  internet_gateway_id = aws_internet_gateway.internet_gateway.id
  vpc_id              = aws_vpc.vpc.id
}
resource "aws_route_table" "public_subnet_route_table" {
  tags = {
    Name = "public-rt"
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_route" "public_subnet_route" {
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.internet_gateway.id
  route_table_id         = aws_route_table.public_subnet_route_table.id
}
resource "aws_subnet" "public_subneta" {
  availability_zone       = "${data.aws_region.current.region}a"
  cidr_block              = local.mappings["AzMapping"]["a"]["PublicSubnetCidr"]
  map_public_ip_on_launch = true
  tags = {
    Name = "public-subnet-a"
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_route_table_association" "public_subneta_route_table_association" {
  route_table_id = aws_route_table.public_subnet_route_table.id
  subnet_id      = aws_subnet.public_subneta.id
}
resource "aws_subnet" "public_subnetb" {
  availability_zone       = "${data.aws_region.current.region}b"
  cidr_block              = local.mappings["AzMapping"]["b"]["PublicSubnetCidr"]
  map_public_ip_on_launch = true
  tags = {
    Name = "public-subnet-b"
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_route_table_association" "public_subnetb_route_table_association" {
  route_table_id = aws_route_table.public_subnet_route_table.id
  subnet_id      = aws_subnet.public_subnetb.id
}
resource "aws_subnet" "private_subneta" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = local.mappings["AzMapping"]["a"]["PrivateSubnetCidr"]
  availability_zone = "${data.aws_region.current.region}a"
  tags = {
    Name = "private-subnet-a"
  }
}
resource "aws_route_table" "private_subneta_route_table" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "private-rt-a"
  }
}
resource "aws_eip" "natgatewaya_elastic_ip" {}
resource "aws_nat_gateway" "nat_gatewaya" {
  allocation_id = aws_eip.natgatewaya_elastic_ip.allocation_id
  subnet_id     = aws_subnet.public_subneta.id
  tags = {
    Name = "natgw-a"
  }
}
resource "aws_route_table_association" "private_subneta_route_table_association" {
  route_table_id = aws_route_table.private_subneta_route_table.id
  subnet_id      = aws_subnet.private_subneta.id
}
resource "aws_route" "private_subneta_route" {
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gatewaya.id
  route_table_id         = aws_route_table.private_subneta_route_table.id
}
resource "aws_subnet" "private_subnetb" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = local.mappings["AzMapping"]["b"]["PrivateSubnetCidr"]
  availability_zone = "${data.aws_region.current.region}b"
  tags = {
    Name = "private-subnet-b"
  }
}
resource "aws_route_table" "private_subnetb_route_table" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "private-rt-b"
  }
}
resource "aws_eip" "natgatewayb_elastic_ip" {}
resource "aws_nat_gateway" "nat_gatewayb" {
  allocation_id = aws_eip.natgatewayb_elastic_ip.allocation_id
  subnet_id     = aws_subnet.public_subnetb.id
  tags = {
    Name = "natgw-b"
  }
}
resource "aws_route_table_association" "private_subnetb_route_table_association" {
  route_table_id = aws_route_table.private_subnetb_route_table.id
  subnet_id      = aws_subnet.private_subnetb.id
}
resource "aws_route" "private_subnetb_route" {
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gatewayb.id
  route_table_id         = aws_route_table.private_subnetb_route_table.id
}
# CreationPolicy: CloudFormation CreationPolicy (cfn-signal) has no Terraform equivalent; the wait is not reproduced.
# # {
# #   "ResourceSignal": {
# #     "Count": "1",
# #     "Timeout": "PT7M"
# #   }
# # }
resource "aws_instance" "vs_code_ec2" {
  ami           = data.aws_ssm_parameter.ami_id.insecure_value
  instance_type = "t3.medium"
  key_name      = aws_key_pair.key_pair.key_name
  tags = {
    Name = "vscode"
  }
  iam_instance_profile        = aws_iam_instance_profile.vs_code_ec2_instance_profile.name
  user_data                   = <<EOT
#!/bin/bash
dnf update -yq
dnf groupinstall -yq "Development Tools"
dnf install -yq git

export VSC_VERSION="4.102.3"
wget -q https://github.com/coder/code-server/releases/download/v$VSC_VERSION/code-server-$VSC_VERSION-linux-amd64.tar.gz
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

dnf install -yq python3.13
ln -sf /usr/bin/python3.13 /usr/bin/python
python -m ensurepip --upgrade

dnf install -yq docker
dnf install -yq bash-completion
systemctl enable --now docker
# usermod -aG docker ec2-user
# newgrp docker
chmod 666 /var/run/docker.sock

/opt/aws/bin/cfn-signal -e $? --stack ${var.stack_name} --resource VsCodeEc2 --region ${data.aws_region.current.region}
EOT
  subnet_id                   = aws_subnet.public_subneta.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.vs_code_ec2_security_group.id]
}
resource "aws_security_group" "vs_code_ec2_security_group" {
  description = "Security Group"
  name        = "bastion-sg"
  dynamic "ingress" {
    for_each = local.cond_security_group_inbound_from_anywhere ? [1] : []
    content {
      protocol    = "tcp"
      from_port   = 8000
      to_port     = 8000
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_iam_role" "vs_code_ec2_iam_role" {
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
resource "aws_iam_instance_profile" "vs_code_ec2_instance_profile" {
  # An instance profile holds at most one role, so this attribute is a single
  # role name string - not the list CloudFormation's AWS::IAM::InstanceProfile
  # Roles property takes. jsonencode([...]) here sends the literal string
  # ["terraform-..."] as roleName, which IAM rejects with a ValidationError
  # during apply, while terraform validate and plan both pass because the
  # attribute is a string either way (rules.md A-3).
  role = aws_iam_role.vs_code_ec2_iam_role.name
}
resource "aws_ecs_cluster" "ecs_cluster" {
  setting {
    name  = "containerInsights"
    value = "enhanced"
  }
  service_connect_defaults {
    namespace = aws_service_discovery_http_namespace.service_connect_namespace.arn
  }
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  name = "${var.stack_name}-ecs-cluster"
}
resource "aws_ecs_capacity_provider" "ecs_ec2_capacity_provider" {
  auto_scaling_group_provider {
    auto_scaling_group_arn = aws_autoscaling_group.ecs_asg.arn
    managed_draining       = "ENABLED"
    managed_scaling {
      instance_warmup_period    = 30
      maximum_scaling_step_size = 10000
      minimum_scaling_step_size = 1
      status                    = "ENABLED"
      target_capacity           = 100
    }
    managed_termination_protection = "DISABLED"
  }
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  name = "${var.stack_name}-ecs-ec2-capacity-provider"
}
resource "aws_ecs_cluster_capacity_providers" "ecs_ec2_capacity_provider_association" {
  capacity_providers = [aws_ecs_capacity_provider.ecs_ec2_capacity_provider.id, "FARGATE", "FARGATE_SPOT"]
  cluster_name       = aws_ecs_cluster.ecs_cluster.name
  default_capacity_provider_strategy {
    base              = 0
    capacity_provider = aws_ecs_capacity_provider.ecs_ec2_capacity_provider.id
    weight            = 100
  }
}
resource "aws_autoscaling_group" "ecs_asg" {
  min_size            = 1
  desired_capacity    = 2
  max_size            = 6
  vpc_zone_identifier = [aws_subnet.private_subneta.id, aws_subnet.private_subnetb.id]
  launch_template {
    id      = aws_launch_template.ecs_lt.id
    version = aws_launch_template.ecs_lt.latest_version
  }
  availability_zone_distribution {
    capacity_distribution_strategy = "balanced-only"
  }
  depends_on = [aws_ecs_cluster.ecs_cluster]
}
resource "aws_launch_template" "ecs_lt" {
  image_id      = data.aws_ssm_parameter.ecs_ami_id.insecure_value
  instance_type = "t3.medium"
  iam_instance_profile {
    name = aws_iam_instance_profile.ecs_container_instance_profile.name
  }
  vpc_security_group_ids = [aws_security_group.ecs_container_instance_security_group.id]
  user_data = base64encode(<<EOT
#!/bin/bash -xe
echo ECS_CLUSTER=${aws_ecs_cluster.ecs_cluster.name} >> /etc/ecs/ecs.config
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
  # Single role name string, not a list (rules.md A-3).
  role = aws_iam_role.ecs_container_instance_iam_role.name
}
resource "aws_iam_role" "ecs_task_role" {
  name = "EcsTaskIamRole-${local.stack_suffix}"
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
  name = "EcsTaskExecutionIamRole-${local.stack_suffix}"
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
resource "aws_cloudwatch_log_group" "ecs_task_cloud_watch_log_group" {
  name = "/aws/ecs/${local.stack_suffix}"
}
resource "aws_security_group" "ecs_service_security_group" {
  name        = "ecs-service-sg"
  description = "Security Group"
  vpc_id      = aws_vpc.vpc.id
}
resource "aws_vpc_security_group_ingress_rule" "ecs_service_security_group_ingress" {
  security_group_id            = aws_security_group.ecs_service_security_group.id
  referenced_security_group_id = aws_security_group.ecs_service_security_group.id
  ip_protocol                  = -1
}
resource "aws_service_discovery_http_namespace" "service_connect_namespace" {
  name        = "service-connect-test"
  description = "Namespace for ECS Service Connect"
}
resource "aws_ecs_task_definition" "app_task_definition" {
  family                   = "nginx-td"
  network_mode             = "awsvpc"
  requires_compatibilities = ["EC2"]
  cpu                      = 256
  memory                   = 512
  task_role_arn            = aws_iam_role.ecs_task_role.name
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.name
  container_definitions = jsonencode([{
    Name      = "nginx"
    Image     = "nginx:latest"
    Essential = true
    PortMappings = [{
      ContainerPort = 80
      Protocol      = "tcp"
      Name          = "http"
    }]
    LogConfiguration = {
      LogDriver = "awslogs"
      Options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ecs_task_cloud_watch_log_group.name
        "awslogs-region"        = data.aws_region.current.region
        "awslogs-stream-prefix" = "ecs-app-"
      }
    }
  }])
}
resource "aws_ecs_service" "app_service" {
  cluster         = aws_ecs_cluster.ecs_cluster.name
  task_definition = aws_ecs_task_definition.app_task_definition.arn
  desired_count   = 3
  network_configuration {
    security_groups = [aws_security_group.ecs_service_security_group.id]
    subnets         = [aws_subnet.private_subneta.id, aws_subnet.private_subnetb.id]
  }
  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ecs_ec2_capacity_provider.id
    weight            = 1
  }
  service_connect_configuration {
    enabled = true
    service {
      port_name      = "http"
      discovery_name = "nginx"
      client_alias {
        port     = 80
        dns_name = "nginx.local"
      }
    }
  }
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  name = "${var.stack_name}-app-service"
}
resource "aws_ecs_task_definition" "dnsutils_task_definition" {
  family                   = "dnsutils-td"
  network_mode             = "awsvpc"
  requires_compatibilities = ["EC2"]
  cpu                      = 256
  memory                   = 512
  task_role_arn            = aws_iam_role.ecs_task_role.name
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.name
  container_definitions = jsonencode([{
    Name      = "dnsutils"
    Image     = "registry.k8s.io/e2e-test-images/agnhost:2.50"
    Essential = true
    LogConfiguration = {
      LogDriver = "awslogs"
      Options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ecs_task_cloud_watch_log_group.name
        "awslogs-region"        = data.aws_region.current.region
        "awslogs-stream-prefix" = "ecs-dnsutils-"
      }
    }
  }])
}
resource "aws_ecs_service" "dnsutils_service" {
  cluster                = aws_ecs_cluster.ecs_cluster.name
  task_definition        = aws_ecs_task_definition.dnsutils_task_definition.arn
  desired_count          = 1
  enable_execute_command = true
  network_configuration {
    security_groups = [aws_security_group.ecs_service_security_group.id]
    subnets         = [aws_subnet.private_subneta.id, aws_subnet.private_subnetb.id]
  }
  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ecs_ec2_capacity_provider.id
    weight            = 1
  }
  service_connect_configuration {
    enabled = true
  }
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  name = "${var.stack_name}-dnsutils-service"
}
# --- Outputs ---
# CloudFormation output: VsCode
output "vs_code" {
  value       = "http://${aws_instance.vs_code_ec2.public_ip}:8000"
  description = "Public IP Address of the VS Code"
}
# CloudFormation output: ServiceConnectTestCommands
output "service_connect_test_commands" {
  value       = "aws ecs execute-command\n --cluster ${aws_ecs_cluster.ecs_cluster.name}\n --task $(aws ecs list-tasks --cluster ${aws_ecs_cluster.ecs_cluster.name} --service-name ${aws_ecs_service.dnsutils_service.name} --query \"taskArns[0]\" --output text | cut -d\"/\" -f3)\n --container dnsutils\n --interactive\n --command \"/bin/sh\"\n"
  description = "ECS Exec Command"
}
