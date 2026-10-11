# Generated from 124_ecs_managed_instances/url_shortener.yaml by tools/cfn2tf.
# CloudFormation stack -> Terraform root module.
terraform {
  required_version = ">= 1.9"
  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 6.0" }
    archive = { source = "hashicorp/archive", version = "~> 2.4" }
    random  = { source = "hashicorp/random", version = "~> 3.6" }
    tls     = { source = "hashicorp/tls", version = "~> 4.0" }
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
  default     = "url-shortener"
  description = "Stands in for AWS::StackName."
}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}
# Provides the unique suffix that AWS::StackId supplies in CloudFormation.
resource "random_uuid" "stack_id" {}
# --- Parameters ---
variable "default_domain" {
  type        = string
  description = "example.com"
}
variable "default_domain_route53_hosted_zone" {
  type        = string
  description = "Shlink Default Domain Name (Public Hosted Zone should be already created)"
}
variable "inbound_from_anywhere" {
  type        = string
  default     = "True"
  description = "SecurityGroup Inbound Rule (Source 0.0.0.0/0)"
  validation {
    condition     = contains(["True", "False"], var.inbound_from_anywhere)
    error_message = "InboundFromAnywhere must be one of: True, False"
  }
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
  stack_id                                  = "arn:${data.aws_partition.current.partition}:cloudformation:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:stack/${var.stack_name}/${random_uuid.stack_id.result}"
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
resource "aws_iam_role_policy_attachment" "ecs_infrastructure_role" {
  role       = aws_iam_role.ecs_infrastructure_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonECSInfrastructureRolePolicyForManagedInstances"
}
resource "aws_iam_role_policy_attachment" "ecs_instance_role_0" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}
resource "aws_iam_role_policy_attachment" "ecs_instance_role_1" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
resource "aws_iam_role_policy" "ecs_task_execution_role" {
  name = "AllowSecretManagerGetSecretValue"
  role = aws_iam_role.ecs_task_execution_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "secretsmanager:GetSecretValue"
      Resource = aws_secretsmanager_secret.secret.arn
    }]
  })
}
resource "aws_iam_role_policy_attachment" "ecs_task_execution_role" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
resource "aws_iam_role_policy" "ecs_task_role" {
  name = "AllowEfsClient"
  role = aws_iam_role.ecs_task_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["elasticfilesystem:ClientMount", "elasticfilesystem:ClientWrite"]
      Resource = aws_efs_file_system.efs_file_system.arn
      Condition = {
        StringEquals = {
          "elasticfilesystem:AccessPointArn" = aws_efs_access_point.efs_access_point.arn
        }
      }
    }]
  })
}
resource "aws_efs_backup_policy" "efs_file_system" {
  file_system_id = aws_efs_file_system.efs_file_system.id
  backup_policy {
    status = "ENABLED"
  }
}
resource "aws_secretsmanager_secret_version" "secret" {
  secret_id     = aws_secretsmanager_secret.secret.id
  secret_string = <<EOT
{
  "DEFAULT_DOMAIN":"shlink.${var.default_domain}",
  "IS_HTTPS_ENABLED":"true",
  "SHLINK_API_KEY":"${aws_lambda_invocation.api_key.id}",
  "SHLINK_SERVER_URL":"https://shlink.${var.default_domain}",
  "SHLINK_SERVER_NAME":"shlink",
  "SHLINK_PORT":"8080",
  "WEB_CLIENT_PORT":"8000",
  "TIMEZONE":"Asia/Seoul"
}
EOT
}
data "archive_file" "secret_manager_lambda_function" {
  type        = "zip"
  source_file = "${path.module}/lambda_src/secret_manager_lambda_function/index.py"
  output_path = "${path.module}/build/secret_manager_lambda_function.zip"
}
resource "aws_iam_role_policy_attachment" "secret_manager_lambda_iam_role" {
  role       = aws_iam_role.secret_manager_lambda_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
data "aws_route53_zone" "route53_record_zone" {
  name = "${var.default_domain}."
}
data "archive_file" "ecs_lambda_function" {
  type        = "zip"
  source_file = "${path.module}/lambda_src/ecs_lambda_function/index.py"
  output_path = "${path.module}/build/ecs_lambda_function.zip"
}
resource "aws_iam_role_policy" "ecs_lambda_iam_role" {
  name = "AllowSecretManagerGetSecretValue"
  role = aws_iam_role.ecs_lambda_iam_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ecs:UpdateService", "ecs:DescribeClusters"]
      Resource = "*"
    }]
  })
}
resource "aws_iam_role_policy_attachment" "ecs_lambda_iam_role" {
  role       = aws_iam_role.ecs_lambda_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
# --- Resources ---
resource "aws_key_pair" "key_pair" {
  key_name   = "key-${element(split("-", element(split("/", local.stack_id), 2)), 3)}"
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
resource "aws_subnet" "public_subnetc" {
  availability_zone       = "${data.aws_region.current.region}c"
  cidr_block              = local.mappings["AzMapping"]["c"]["PublicSubnetCidr"]
  map_public_ip_on_launch = true
  tags = {
    Name = "public-subnet-c"
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_route_table_association" "public_subnetc_route_table_association" {
  route_table_id = aws_route_table.public_subnet_route_table.id
  subnet_id      = aws_subnet.public_subnetc.id
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
  depends_on             = [aws_internet_gateway_attachment.vpc_internet_gateway_attachment]
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
resource "aws_subnet" "private_subnetc" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = local.mappings["AzMapping"]["c"]["PrivateSubnetCidr"]
  availability_zone = "${data.aws_region.current.region}c"
  tags = {
    Name = "private-subnet-c"
  }
}
resource "aws_route_table" "private_subnetc_route_table" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "private-rt-c"
  }
}
resource "aws_eip" "natgatewayc_elastic_ip" {}
resource "aws_nat_gateway" "nat_gatewayc" {
  allocation_id = aws_eip.natgatewayc_elastic_ip.allocation_id
  subnet_id     = aws_subnet.public_subnetc.id
  tags = {
    Name = "natgw-c"
  }
}
resource "aws_route_table_association" "private_subnetc_route_table_association" {
  route_table_id = aws_route_table.private_subnetc_route_table.id
  subnet_id      = aws_subnet.private_subnetc.id
}
resource "aws_route" "private_subnetc_route" {
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gatewayc.id
  route_table_id         = aws_route_table.private_subnetc_route_table.id
}
resource "aws_ecs_cluster" "ecs_cluster" {
  setting {
    name  = "containerInsights"
    value = "enhanced"
  }
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  name = "${var.stack_name}-ecs-cluster"
}
resource "aws_ecs_capacity_provider" "managed_instances_capacity_provider" {
  # TODO cfn2tf: unmapped CloudFormation property 'ClusterName' of AWS::ECS::CapacityProvider
  # # {
  # #   "Ref": "EcsCluster"
  # # }
  managed_instances_provider {
    infrastructure_role_arn = aws_iam_role.ecs_infrastructure_role.arn
    infrastructure_optimization {
      scale_in_after = 0
    }
    # TODO cfn2tf: unmapped CloudFormation property 'AutoRepairConfiguration' of AWS::ECS::CapacityProvider
    # # {
    # #   "ActionsStatus": "ENABLED"
    # # }
    instance_launch_template {
      ec2_instance_profile_arn = aws_iam_instance_profile.ecs_instance_profile.arn
      capacity_option_type     = "ON_DEMAND"
      monitoring               = "BASIC"
      network_configuration {
        subnets         = [aws_subnet.private_subneta.id, aws_subnet.private_subnetc.id]
        security_groups = [aws_security_group.ecs_managed_instances_security_group.id]
      }
      storage_configuration {
        storage_size_gib = 30
      }
      instance_requirements {
        vcpu_count {
          min = 1
          max = 4
        }
        memory_mib {
          min = 2048
          max = 8192
        }
      }
    }
  }
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  name = "${var.stack_name}-managed-instances-capacity-provider"
}
resource "aws_iam_role" "ecs_infrastructure_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ecs.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}
resource "aws_iam_role" "ecs_instance_role" {
  name = "ecsInstanceRole-${element(split("-", element(split("/", local.stack_id), 2)), 3)}"
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
resource "aws_iam_instance_profile" "ecs_instance_profile" {
  # An instance profile holds at most one role, so this attribute is a single
  # role name string - not the list CloudFormation's AWS::IAM::InstanceProfile
  # Roles property takes. jsonencode([...]) here sends the literal string
  # ["terraform-..."] as roleName, which IAM rejects with a ValidationError
  # during apply, while terraform validate and plan both pass because the
  # attribute is a string either way (rules.md A-3).
  role = aws_iam_role.ecs_instance_role.name
}
resource "aws_security_group" "ecs_managed_instances_security_group" {
  description = "Security Group"
  vpc_id      = aws_vpc.vpc.id
}
resource "aws_ecs_task_definition" "shlink_task_definition" {
  family = "shlink"
  container_definitions = jsonencode([{
    Name      = "shlink"
    Image     = "shlinkio/shlink:stable"
    Essential = true
    LogConfiguration = {
      LogDriver = "awslogs"
      Options = {
        "awslogs-group"         = aws_cloudwatch_log_group.shlink_log_group.name
        "awslogs-region"        = data.aws_region.current.region
        "awslogs-stream-prefix" = "ecs"
        mode                    = "non-blocking"
        "max-buffer-size"       = "25m"
      }
    }
    HealthCheck = {
      Command     = ["CMD-SHELL", "wget --spider -q http://127.0.0.1:8080/rest/health || exit 1"]
      Interval    = 30
      Timeout     = 5
      Retries     = 5
      StartPeriod = 10
    }
    PortMappings = [{
      ContainerPort = 8080
      Protocol      = "tcp"
    }]
    Secrets = [{
      Name      = "DEFAULT_DOMAIN"
      ValueFrom = "${aws_secretsmanager_secret.secret.arn}:DEFAULT_DOMAIN::"
      }, {
      Name      = "IS_HTTPS_ENABLED"
      ValueFrom = "${aws_secretsmanager_secret.secret.arn}:IS_HTTPS_ENABLED::"
      }, {
      Name      = "TIMEZONE"
      ValueFrom = "${aws_secretsmanager_secret.secret.arn}:TIMEZONE::"
      }, {
      Name      = "INITIAL_API_KEY"
      ValueFrom = "${aws_secretsmanager_secret.secret.arn}:SHLINK_API_KEY::"
    }]
    MountPoints = [{
      SourceVolume  = "shlink_data"
      ContainerPath = "/etc/shlink/data"
      ReadOnly      = false
    }]
  }])
  cpu                      = 512
  memory                   = 1024
  network_mode             = "awsvpc"
  requires_compatibilities = ["MANAGED_INSTANCES"]
  runtime_platform {
    cpu_architecture        = "X86_64"
    operating_system_family = "LINUX"
  }
  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn      = aws_iam_role.ecs_task_role.arn
  volume {
    name = "shlink_data"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.efs_file_system.id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.efs_access_point.id
        iam             = "ENABLED"
      }
    }
  }
}
resource "aws_cloudwatch_log_group" "shlink_log_group" {
  name              = "/ecs/task/shlink"
  retention_in_days = 30
}
resource "aws_security_group" "shlink_service_security_group" {
  description = "Security Group"
  vpc_id      = aws_vpc.vpc.id
  ingress {
    protocol        = "tcp"
    from_port       = 8080
    to_port         = 8080
    security_groups = [aws_security_group.shlink_alb_security_group.id]
    description     = "ALB"
  }
}
resource "aws_ecs_service" "shlink_service" {
  cluster         = aws_ecs_cluster.ecs_cluster.name
  task_definition = aws_ecs_task_definition.shlink_task_definition.arn
  desired_count   = 1
  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.managed_instances_capacity_provider.id
    weight            = 100
  }
  health_check_grace_period_seconds = 60
  load_balancer {
    container_name   = "shlink"
    container_port   = 8080
    target_group_arn = aws_lb_target_group.shlink_alb_target_group.arn
  }
  network_configuration {
    subnets         = [aws_subnet.private_subneta.id, aws_subnet.private_subnetc.id]
    security_groups = [aws_security_group.shlink_service_security_group.id]
  }
  deployment_maximum_percent         = 100
  deployment_minimum_healthy_percent = 0
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  name       = "${var.stack_name}-shlink-service"
  depends_on = [aws_efs_mount_target.efs_mount_targeta, aws_efs_mount_target.efs_mount_targetc, aws_lb_listener.shlink_alb_listener]
}
resource "aws_ecs_task_definition" "web_client_task_definition" {
  family = "shlink-web-client"
  container_definitions = jsonencode([{
    Name      = "shlink-web-client"
    Image     = "shlinkio/shlink-web-client:stable"
    Essential = true
    LogConfiguration = {
      LogDriver = "awslogs"
      Options = {
        "awslogs-group"         = aws_cloudwatch_log_group.web_client_log_group.name
        "awslogs-region"        = data.aws_region.current.region
        "awslogs-stream-prefix" = "ecs"
        mode                    = "non-blocking"
        "max-buffer-size"       = "25m"
      }
    }
    PortMappings = [{
      ContainerPort = 8080
      Protocol      = "tcp"
    }]
    Secrets = [{
      Name      = "SHLINK_SERVER_URL"
      ValueFrom = "${aws_secretsmanager_secret.secret.arn}:SHLINK_SERVER_URL::"
      }, {
      Name      = "SHLINK_SERVER_NAME"
      ValueFrom = "${aws_secretsmanager_secret.secret.arn}:SHLINK_SERVER_NAME::"
      }, {
      Name      = "SHLINK_SERVER_API_KEY"
      ValueFrom = "${aws_secretsmanager_secret.secret.arn}:SHLINK_API_KEY::"
    }]
  }])
  cpu                      = 256
  memory                   = 512
  network_mode             = "awsvpc"
  requires_compatibilities = ["MANAGED_INSTANCES"]
  runtime_platform {
    cpu_architecture        = "X86_64"
    operating_system_family = "LINUX"
  }
  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn
}
resource "aws_cloudwatch_log_group" "web_client_log_group" {
  name              = "/ecs/task/web-client"
  retention_in_days = 30
}
resource "aws_security_group" "web_client_service_security_group" {
  description = "Security Group"
  vpc_id      = aws_vpc.vpc.id
  ingress {
    protocol        = "tcp"
    from_port       = 8080
    to_port         = 8080
    security_groups = [aws_security_group.web_client_alb_security_group.id]
    description     = "ALB"
  }
}
resource "aws_ecs_service" "web_client_service" {
  cluster         = aws_ecs_cluster.ecs_cluster.name
  task_definition = aws_ecs_task_definition.web_client_task_definition.arn
  desired_count   = 1
  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.managed_instances_capacity_provider.id
    weight            = 100
  }
  load_balancer {
    container_name   = "shlink-web-client"
    container_port   = 8080
    target_group_arn = aws_lb_target_group.web_client_alb_target_group.arn
  }
  network_configuration {
    subnets         = [aws_subnet.private_subneta.id, aws_subnet.private_subnetc.id]
    security_groups = [aws_security_group.web_client_service_security_group.id]
  }
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  name       = "${var.stack_name}-web-client-service"
  depends_on = [aws_lb_listener.web_client_alb_listener]
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
resource "aws_efs_file_system" "efs_file_system" {
  encrypted        = true
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"
  tags = {
    Name = "shlink"
  }
  lifecycle {
    prevent_destroy = true
  }
}
resource "aws_efs_access_point" "efs_access_point" {
  file_system_id = aws_efs_file_system.efs_file_system.id
  posix_user {
    uid = 1001
    gid = 1001
  }
  root_directory {
    path = "/shlink"
    creation_info {
      owner_uid   = 1001
      owner_gid   = 1001
      permissions = "0755"
    }
  }
}
resource "aws_efs_mount_target" "efs_mount_targeta" {
  file_system_id  = aws_efs_file_system.efs_file_system.id
  security_groups = [aws_security_group.efs_security_group.id]
  subnet_id       = aws_subnet.private_subneta.id
}
resource "aws_efs_mount_target" "efs_mount_targetc" {
  file_system_id  = aws_efs_file_system.efs_file_system.id
  security_groups = [aws_security_group.efs_security_group.id]
  subnet_id       = aws_subnet.private_subnetc.id
}
resource "aws_security_group" "efs_security_group" {
  description = "Security Group"
  vpc_id      = aws_vpc.vpc.id
  ingress {
    protocol        = "tcp"
    from_port       = 2049
    to_port         = 2049
    security_groups = [aws_security_group.ecs_managed_instances_security_group.id]
    description     = "ECS Managed Instances"
  }
  ingress {
    protocol        = "tcp"
    from_port       = 2049
    to_port         = 2049
    security_groups = [aws_security_group.shlink_service_security_group.id]
    description     = "ECS Task"
  }
}
resource "aws_secretsmanager_secret" "secret" {}
resource "aws_lambda_invocation" "api_key" {
  function_name = aws_lambda_function.secret_manager_lambda_function.arn
  input         = jsonencode({})
}
resource "aws_lambda_function" "secret_manager_lambda_function" {
  runtime          = "python3.14"
  handler          = "index.handler"
  role             = aws_iam_role.secret_manager_lambda_iam_role.arn
  timeout          = 30
  filename         = data.archive_file.secret_manager_lambda_function.output_path
  source_code_hash = data.archive_file.secret_manager_lambda_function.output_base64sha256
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  function_name = "${var.stack_name}-secret-manager-lambda-function"
}
resource "aws_iam_role" "secret_manager_lambda_iam_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}
resource "aws_route53_record" "route53_record" {
  name = "shlink.${var.default_domain}"
  type = "A"
  alias {
    name                   = aws_lb.shlink_alb.dns_name
    evaluate_target_health = false
    zone_id                = aws_lb.shlink_alb.zone_id
  }
  zone_id = data.aws_route53_zone.route53_record_zone.zone_id
}
resource "aws_acm_certificate" "acm_certificate" {
  domain_name       = "shlink.${var.default_domain}"
  key_algorithm     = "RSA_2048"
  validation_method = "DNS"
}
resource "aws_lb" "shlink_alb" {
  load_balancer_type = "application"
  subnets            = [aws_subnet.public_subneta.id, aws_subnet.public_subnetc.id]
  security_groups    = [aws_security_group.shlink_alb_security_group.id]
  internal           = false
}
resource "aws_lb_target_group" "shlink_alb_target_group" {
  vpc_id      = aws_vpc.vpc.id
  target_type = "ip"
  protocol    = "HTTP"
  port        = 8080
  health_check {
    path                = "/rest/health"
    protocol            = "HTTP"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
    enabled             = true
    matcher             = "200"
  }
  deregistration_delay = "30"
}
resource "aws_lb_listener" "shlink_alb_listener" {
  load_balancer_arn = aws_lb.shlink_alb.arn
  protocol          = "HTTPS"
  port              = 443
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.shlink_alb_target_group.arn
  }
  certificate_arn = aws_acm_certificate.acm_certificate.arn
}
resource "aws_lb_listener" "shlink_alb_redirect_listener" {
  load_balancer_arn = aws_lb.shlink_alb.arn
  protocol          = "HTTP"
  port              = 80
  default_action {
    type = "redirect"
    redirect {
      protocol    = "HTTPS"
      port        = 443
      host        = "#{host}"
      path        = "/#{path}"
      query       = "#{query}"
      status_code = "HTTP_301"
    }
  }
}
resource "aws_security_group" "shlink_alb_security_group" {
  description = "Security Group"
  name        = "shlink-alb-sg"
  vpc_id      = aws_vpc.vpc.id
  dynamic "ingress" {
    for_each = local.cond_security_group_inbound_from_anywhere ? [1] : []
    content {
      protocol    = "tcp"
      from_port   = 443
      to_port     = 443
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
  dynamic "ingress" {
    for_each = local.cond_security_group_inbound_from_anywhere ? [1] : []
    content {
      protocol    = "tcp"
      from_port   = 80
      to_port     = 80
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
  tags = {
    Name = "shlink-alb-sg"
  }
}
resource "aws_lb" "web_client_alb" {
  load_balancer_type = "application"
  subnets            = [aws_subnet.public_subneta.id, aws_subnet.public_subnetc.id]
  security_groups    = [aws_security_group.web_client_alb_security_group.id]
  internal           = false
}
resource "aws_lb_target_group" "web_client_alb_target_group" {
  vpc_id      = aws_vpc.vpc.id
  target_type = "ip"
  protocol    = "HTTP"
  port        = 8080
  health_check {
    path                = "/"
    protocol            = "HTTP"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
    enabled             = true
    matcher             = "200-399"
  }
  deregistration_delay = "30"
}
resource "aws_lb_listener" "web_client_alb_listener" {
  load_balancer_arn = aws_lb.web_client_alb.arn
  protocol          = "HTTP"
  port              = 80
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_client_alb_target_group.arn
  }
}
resource "aws_security_group" "web_client_alb_security_group" {
  description = "Security Group"
  name        = "web-client-alb-sg"
  vpc_id      = aws_vpc.vpc.id
  dynamic "ingress" {
    for_each = local.cond_security_group_inbound_from_anywhere ? [1] : []
    content {
      protocol    = "tcp"
      from_port   = 80
      to_port     = 80
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
  tags = {
    Name = "web-client-alb-sg"
  }
}
resource "aws_lambda_invocation" "delete_ecs_managed_instances" {
  function_name = aws_lambda_function.ecs_lambda_function.arn
  input = jsonencode({
    EcsCluster  = aws_ecs_cluster.ecs_cluster.name
    EcsServices = [aws_ecs_service.shlink_service.id, aws_ecs_service.web_client_service.id]
  })
  depends_on = [aws_ecs_capacity_provider.managed_instances_capacity_provider]
}
resource "aws_lambda_function" "ecs_lambda_function" {
  runtime          = "python3.14"
  handler          = "index.handler"
  role             = aws_iam_role.ecs_lambda_iam_role.arn
  timeout          = 900
  filename         = data.archive_file.ecs_lambda_function.output_path
  source_code_hash = data.archive_file.ecs_lambda_function.output_base64sha256
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  function_name = "${var.stack_name}-ecs-lambda-function"
}
resource "aws_iam_role" "ecs_lambda_iam_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}
# --- Outputs ---
# CloudFormation output: ShlinkDomain
output "shlink_domain" {
  value = "https://shlink.${var.default_domain}"
}
# CloudFormation output: ShlinkApiKey
output "shlink_api_key" {
  value = aws_lambda_invocation.api_key.id
}
# CloudFormation output: ShlinkWebClient
output "shlink_web_client" {
  value = "http://${aws_lb.web_client_alb.dns_name}"
}
