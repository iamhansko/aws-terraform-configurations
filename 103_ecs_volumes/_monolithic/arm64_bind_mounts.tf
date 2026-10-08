# Generated from 103_ecs_volumes/arm64_bind_mounts.yaml by tools/cfn2tf.
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
  default     = "arm64-bind-mounts"
  description = "Stands in for AWS::StackName."
}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}
# Provides the unique suffix that AWS::StackId supplies in CloudFormation.
resource "random_uuid" "stack_id" {}
# --- Parameters ---
variable "ami_id" {
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
  description = "(SSM parameter path; resolved by the aws_ssm_parameter data source)"
}
data "aws_ssm_parameter" "ami_id" {
  name = var.ami_id
}
variable "ecs_ami_id" {
  type        = string
  default     = "/aws/service/ecs/optimized-ami/amazon-linux-2023/arm64/recommended/image_id"
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
resource "aws_iam_role_policy_attachment" "ec2_iam_role" {
  role       = aws_iam_role.ec2_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
resource "aws_iam_role_policy_attachment" "ecs_task_role" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSInfrastructureRolePolicyForVolumes"
}
resource "aws_iam_role_policy_attachment" "ecs_task_execution_role" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
resource "aws_iam_role_policy_attachment" "ecs_asg_iam_role_0" {
  role       = aws_iam_role.ecs_asg_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceAutoscaleRole"
}
resource "aws_iam_role_policy_attachment" "ecs_asg_iam_role_1" {
  role       = aws_iam_role.ecs_asg_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
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
resource "aws_internet_gateway" "internet_gateway" {
  tags = {
    Name = "igw"
  }
}
resource "aws_internet_gateway_attachment" "vpc_internet_gateway_attachment" {
  internet_gateway_id = aws_internet_gateway.internet_gateway.id
  vpc_id              = aws_vpc.vpc.id
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
resource "aws_eip" "natgateway_elastic_ipa" {}
resource "aws_route_table_association" "private_subneta_route_table_association" {
  route_table_id = aws_route_table.private_subnet_route_table.id
  subnet_id      = aws_subnet.private_subneta.id
}
resource "aws_subnet" "private_subnetc" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = local.mappings["AzMapping"]["c"]["PrivateSubnetCidr"]
  availability_zone = "${data.aws_region.current.region}c"
  tags = {
    Name = "private-subnet-c"
  }
}
resource "aws_eip" "natgateway_elastic_ipc" {}
resource "aws_route_table_association" "private_subnetc_route_table_association" {
  route_table_id = aws_route_table.private_subnet_route_table.id
  subnet_id      = aws_subnet.private_subnetc.id
}
resource "aws_route_table" "private_subnet_route_table" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "private-rt"
  }
}
resource "aws_route" "private_subnet_route" {
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gateway.id
  route_table_id         = aws_route_table.private_subnet_route_table.id
}
resource "aws_nat_gateway" "nat_gateway" {
  vpc_id            = aws_vpc.vpc.id
  availability_mode = "regional"
  availability_zone_address {
    availability_zone = "${data.aws_region.current.region}a"
    allocation_ids    = [aws_eip.natgateway_elastic_ipa.allocation_id]
  }
  availability_zone_address {
    availability_zone = "${data.aws_region.current.region}c"
    allocation_ids    = [aws_eip.natgateway_elastic_ipc.allocation_id]
  }
  tags = {
    Name = "regional-natgw"
  }
  depends_on = [aws_internet_gateway_attachment.vpc_internet_gateway_attachment]
}
# CreationPolicy: CloudFormation CreationPolicy (cfn-signal) has no Terraform equivalent; the wait is not reproduced.
# # {
# #   "ResourceSignal": {
# #     "Count": "1",
# #     "Timeout": "PT10M"
# #   }
# # }
resource "aws_instance" "ec2" {
  ami           = data.aws_ssm_parameter.ami_id.insecure_value
  instance_type = "t4g.medium"
  key_name      = aws_key_pair.key_pair.key_name
  tags = {
    Name = "arm64"
  }
  iam_instance_profile        = aws_iam_instance_profile.ec2_instance_profile.name
  user_data                   = <<EOT
#!/bin/bash
set -x

dnf install -yq docker
dnf install -yq bash-completion
systemctl enable --now docker
usermod -aG docker ec2-user
newgrp docker

cd /home/ec2-user
cat << $'EOF' > Dockerfile
FROM amazoncorretto:21
RUN yum update -y && \
    yum install -y procps util-linux coreutils && \
    yum clean all
WORKDIR /app
RUN echo $'#!/bin/bash \n\
echo "Starting test" \n\
mkdir -p /app/test \n\
counter=0 \n\
while true; do \n\
  echo "[$counter] Writing 200MB file with direct I/O" \n\
  dd if=/dev/zero of=/app/test/test_$counter.dat bs=1M count=200 oflag=direct 2>&1 | tail -1 \n\
  sync \n\
  echo "[$counter] Current disk usage : " \n\
  du -sh /app/test \n\
  file_count=$(ls -1 /app/test 2>/dev/null | wc -l) \n\
  if [ $file_count -gt 5 ]; then \n\
    echo "Cleaning up old files" \n\
    ls -t /app/test/* | tail -n +6 | xargs rm -f \n\
    sync \n\
  fi \n\
  counter=$((counter + 1)) \n\
  sleep 1 \n\
done' > /app/test.sh
RUN chmod +x /app/test.sh
CMD ["/bin/bash", "/app/test.sh"]
EOF

aws ecr get-login-password --region ${data.aws_region.current.region} | docker login --username AWS --password-stdin ${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.region}.amazonaws.com
docker build -t ${aws_ecr_repository.ecr_repository.repository_url}:latest .
docker push ${aws_ecr_repository.ecr_repository.repository_url}:latest

/opt/aws/bin/cfn-signal -e $? --stack ${var.stack_name} --resource Ec2 --region ${data.aws_region.current.region}
EOT
  subnet_id                   = aws_subnet.public_subneta.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.ec2_security_group.id]
}
resource "aws_security_group" "ec2_security_group" {
  description = "Security Group"
  name        = "ec2-sg"
  vpc_id      = aws_vpc.vpc.id
  tags = {
    Name = "ec2-sg"
  }
}
resource "aws_iam_role" "ec2_iam_role" {
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
resource "aws_iam_instance_profile" "ec2_instance_profile" {
  # An instance profile holds at most one role, so this attribute is a single
  # role name string - not the list CloudFormation's AWS::IAM::InstanceProfile
  # Roles property takes. jsonencode([...]) here sends the literal string
  # ["terraform-..."] as roleName, which IAM rejects with a ValidationError
  # during apply, while terraform validate and plan both pass because the
  # attribute is a string either way (rules.md A-3).
  role = aws_iam_role.ec2_iam_role.name
}
resource "aws_ecr_repository" "ecr_repository" {
  force_delete = true
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  name = "${var.stack_name}-ecr-repository"
}
resource "aws_ecs_task_definition" "ecs_task_definition" {
  family             = "amazoncorretto-td"
  task_role_arn      = aws_iam_role.ecs_task_role.arn
  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn
  container_definitions = jsonencode([{
    Name      = "core"
    Image     = "${aws_ecr_repository.ecr_repository.repository_url}:latest"
    Essential = true
    LogConfiguration = {
      LogDriver = "awslogs"
      Options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ecs_task_cloud_watch_log_group.name
        "awslogs-region"        = data.aws_region.current.region
        "awslogs-stream-prefix" = "amazoncorretto-"
      }
    }
    MountPoints = [{
      ContainerPath = "/app/test"
      SourceVolume  = "host-volume"
      ReadOnly      = false
    }]
  }])
  network_mode = "host"
  cpu          = "2048"
  memory       = "15360"
  volume {
    name      = "host-volume"
    host_path = "/ecs/test"
  }
  depends_on = [aws_instance.ec2]
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
resource "aws_cloudwatch_log_group" "ecs_task_cloud_watch_log_group" {
  name = "/ecs/task"
}
resource "aws_ecs_cluster" "ecs_cluster" {
  setting {
    name  = "containerInsights"
    value = "enhanced"
  }
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  name = "${var.stack_name}-ecs-cluster"
}
resource "aws_ecs_capacity_provider" "ecs_capacity_provider" {
  name = "CapacityProvider"
  auto_scaling_group_provider {
    auto_scaling_group_arn = aws_autoscaling_group.ecs_asg.name
    managed_scaling {
      instance_warmup_period = 30
      status                 = "ENABLED"
      target_capacity        = 100
    }
    managed_termination_protection = "DISABLED"
  }
}
resource "aws_ecs_cluster_capacity_providers" "ecs_capacity_provider_association" {
  cluster_name       = aws_ecs_cluster.ecs_cluster.name
  capacity_providers = [aws_ecs_capacity_provider.ecs_capacity_provider.id]
  default_capacity_provider_strategy {
    base              = 0
    weight            = 1
    capacity_provider = aws_ecs_capacity_provider.ecs_capacity_provider.id
  }
}
resource "aws_autoscaling_group" "ecs_asg" {
  min_size         = 4
  max_size         = 8
  desired_capacity = 4
  default_cooldown = 0
  mixed_instances_policy {
    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.ecs_launch_template.id
        version            = aws_launch_template.ecs_launch_template.latest_version
      }
      override {
        instance_type = "r8g.2xlarge"
      }
    }
    instances_distribution {
      on_demand_base_capacity                  = 0
      on_demand_percentage_above_base_capacity = 0
      spot_allocation_strategy                 = "price-capacity-optimized"
    }
  }
  vpc_zone_identifier = [aws_subnet.private_subneta.id, aws_subnet.private_subnetc.id]
  depends_on          = [aws_ecs_cluster.ecs_cluster]
}
resource "aws_launch_template" "ecs_launch_template" {
  image_id = data.aws_ssm_parameter.ecs_ami_id.insecure_value
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "container-instance"
    }
  }
  network_interfaces {
    device_index          = 0
    delete_on_termination = true
    security_groups       = [aws_security_group.ecs_asg_security_group.id]
  }
  key_name = aws_key_pair.key_pair.key_name
  iam_instance_profile {
    arn = aws_iam_instance_profile.ecs_asg_profile.arn
  }
  user_data = base64encode(<<EOT
#!/bin/bash
mkdir -p /etc/ecs
echo "ECS_CLUSTER=${aws_ecs_cluster.ecs_cluster.name}" > /etc/ecs/ecs.config
EOT
  )
}
resource "aws_security_group" "ecs_asg_security_group" {
  description = "Security Group for ASG"
  name        = "container-instance-sg"
  vpc_id      = aws_vpc.vpc.id
}
resource "aws_iam_role" "ecs_asg_iam_role" {
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
resource "aws_iam_instance_profile" "ecs_asg_profile" {
  # Single role name string, not a list (rules.md A-3).
  role = aws_iam_role.ecs_asg_iam_role.name
}
resource "aws_ecs_service" "ecs_service" {
  cluster             = aws_ecs_cluster.ecs_cluster.name
  task_definition     = aws_ecs_task_definition.ecs_task_definition.arn
  scheduling_strategy = "REPLICA"
  desired_count       = 2
  service_connect_configuration {
    enabled = false
  }
  ordered_placement_strategy {
    field = "attribute:ecs.availability-zone"
    type  = "spread"
  }
  ordered_placement_strategy {
    field = "instanceId"
    type  = "spread"
  }
  enable_ecs_managed_tags = true
  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ecs_capacity_provider.id
    base              = 0
    weight            = 1
  }
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  name       = "${var.stack_name}-ecs-service"
  depends_on = [aws_cloudwatch_log_group.ecs_task_cloud_watch_log_group]
}
