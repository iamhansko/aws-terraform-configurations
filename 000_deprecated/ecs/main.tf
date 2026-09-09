# Generated from 000_deprecated/ecs.yaml by tools/cfn2tf.
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
  default     = "ecs"
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
        AmazonLinux2023             = "ami-0b72821e2f351e396"
        EcsOptimizedAmazonLinux2023 = "ami-025a8beccff4de554"
      }
      "ap-northeast-2" = {
        AmazonLinux2023             = "ami-04ea5b2d3c8ceccf8"
        EcsOptimizedAmazonLinux2023 = "ami-0856df28f23817b2f"
      }
    }
    ResourceMap = {
      Vpc = {
        Name      = "stem-vpc"
        CidrBlock = "10.10.0.0/16"
      }
      PublicSubnet = {
        Name = "stem-pub"
      }
      PrivateSubnet = {
        Name = "stem-priv"
      }
      InternetGateway = {
        Name = "stem-igw"
      }
      NatGateway = {
        Name = "stem-natgw"
      }
      BastionEc2 = {
        Name         = "stem-bastion"
        InstanceType = "t3.small"
      }
      CodePipeline = {
        Name              = "stem-pipeline"
        Build             = "stem-build"
        DeployApplication = "stem-app"
        DeploymentGroup   = "stem-dg"
        CloudTrail        = "codepipeline-source-trail"
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
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
resource "aws_iam_role_policy_attachment" "ecs_auto_scaling_group_iam_role_0" {
  role       = aws_iam_role.ecs_auto_scaling_group_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceAutoscaleRole"
}
resource "aws_iam_role_policy_attachment" "ecs_auto_scaling_group_iam_role_1" {
  role       = aws_iam_role.ecs_auto_scaling_group_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}
resource "aws_iam_role_policy_attachment" "ecs_task_execution_role" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
resource "aws_s3_bucket_versioning" "code_pipeline_source_s3_bucket_versioning" {
  bucket = aws_s3_bucket.code_pipeline_source_s3_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}
resource "aws_iam_role_policy" "code_build_iam_role" {
  name = "CodeBuildPolicy"
  role = aws_iam_role.code_build_iam_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:PutObject", "logs:PutLogEvents", "logs:CreateLogGroup", "logs:CreateLogStream", "ecr:GetAuthorizationToken", "ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer", "ecr:GetRepositoryPolicy", "ecr:DescribeRepositories", "ecr:ListImages", "ecr:DescribeImages", "ecr:BatchGetImage", "ecr:GetLifecyclePolicy", "ecr:GetLifecyclePolicyPreview", "ecr:ListTagsForResource", "ecr:DescribeImageScanFindings", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload", "ecr:PutImage", "ecs:*", "iam:PassRole"]
      Resource = "*"
    }]
  })
}
resource "aws_iam_role_policy" "code_deploy_iam_role" {
  name = "CodeDeployPolicy"
  role = aws_iam_role.code_deploy_iam_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ecs:DescribeServices", "ecs:CreateTaskSet", "ecs:UpdateServicePrimaryTaskSet", "ecs:DeleteTaskSet", "elasticloadbalancing:DescribeTargetGroups", "elasticloadbalancing:DescribeListeners", "elasticloadbalancing:ModifyListener", "elasticloadbalancing:DescribeRules", "elasticloadbalancing:ModifyRule", "lambda:InvokeFunction", "cloudwatch:DescribeAlarms", "sns:Publish", "s3:GetObject", "s3:GetObjectVersion"]
      Resource = "*"
      }, {
      Effect   = "Allow"
      Action   = ["iam:PassRole"]
      Resource = "*"
      Condition = {
        StringLike = {
          "iam:PassedToService" = "ecs-tasks.amazonaws.com"
        }
      }
    }]
  })
}
resource "aws_iam_role_policy" "code_pipeline_iam_role" {
  name = "CodePipelinePolicy"
  role = aws_iam_role.code_pipeline_iam_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["codepipeline:StartPipelineExecution"]
      Resource = ["arn:aws:codepipeline:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:${local.mappings["ResourceMap"]["CodePipeline"]["Name"]}"]
      }, {
      Effect   = "Allow"
      Action   = ["codebuild:StartBuild", "codebuild:BatchGetBuilds"]
      Resource = [aws_codebuild_project.code_build.arn]
      }, {
      Effect   = "Allow"
      Action   = ["codedeploy:CreateDeployment", "codedeploy:GetDeployment"]
      Resource = ["arn:aws:codedeploy:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:deploymentgroup:${local.mappings["ResourceMap"]["CodePipeline"]["DeployApplication"]}/${local.mappings["ResourceMap"]["CodePipeline"]["DeploymentGroup"]}"]
      }, {
      Effect   = "Allow"
      Action   = ["codedeploy:GetDeploymentConfig"]
      Resource = ["arn:aws:codedeploy:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:deploymentconfig:CodeDeployDefault.ECSAllAtOnce"]
      }, {
      Effect   = "Allow"
      Action   = ["codedeploy:RegisterApplicationRevision", "codedeploy:GetApplicationRevision"]
      Resource = ["arn:aws:codedeploy:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:application:${local.mappings["ResourceMap"]["CodePipeline"]["DeployApplication"]}"]
      }, {
      Effect   = "Allow"
      Action   = ["s3:*"]
      Resource = "*"
    }]
  })
}
resource "aws_cloudwatch_event_target" "cloud_watch_event_rule" {
  rule      = aws_cloudwatch_event_rule.cloud_watch_event_rule.name
  arn       = "arn:aws:codepipeline:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:${local.mappings["ResourceMap"]["CodePipeline"]["Name"]}"
  target_id = "codepipeline-codepipeline"
  role_arn  = aws_iam_role.cloud_watch_event_rule_iam_role.arn
}
resource "aws_iam_role_policy" "cloud_watch_event_rule_iam_role" {
  name = "CloudWatchEventRulePolicy"
  role = aws_iam_role.cloud_watch_event_rule_iam_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["codepipeline:StartPipelineExecution"]
      Resource = ["arn:aws:codepipeline:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:${local.mappings["ResourceMap"]["CodePipeline"]["Name"]}"]
    }]
  })
}
# --- Resources ---
resource "aws_key_pair" "key_pair" {
  key_name   = "key-${element(split("-", element(split("/", local.stack_id), 2)), 3)}"
  public_key = tls_private_key.key_pair.public_key_openssh
}
resource "aws_vpc" "vpc" {
  enable_dns_hostnames = true
  cidr_block           = local.mappings["ResourceMap"]["Vpc"]["CidrBlock"]
  tags = {
    Name = local.mappings["ResourceMap"]["Vpc"]["Name"]
  }
}
resource "aws_subnet" "public_subnet_a" {
  availability_zone = "${data.aws_region.current.region}a"
  cidr_block        = element([for __i in range(16) : cidrsubnet(aws_vpc.vpc.cidr_block, 32 - 8 - tonumber(split("/", aws_vpc.vpc.cidr_block)[1]), __i)], 0)
  tags = {
    Name = join("-", [local.mappings["ResourceMap"]["PublicSubnet"]["Name"], "a"])
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_subnet" "public_subnet_b" {
  availability_zone = "${data.aws_region.current.region}b"
  cidr_block        = element([for __i in range(16) : cidrsubnet(aws_vpc.vpc.cidr_block, 32 - 8 - tonumber(split("/", aws_vpc.vpc.cidr_block)[1]), __i)], 1)
  tags = {
    Name = join("-", [local.mappings["ResourceMap"]["PublicSubnet"]["Name"], "b"])
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_subnet" "private_subnet_a" {
  availability_zone = "${data.aws_region.current.region}a"
  cidr_block        = element([for __i in range(16) : cidrsubnet(aws_vpc.vpc.cidr_block, 32 - 8 - tonumber(split("/", aws_vpc.vpc.cidr_block)[1]), __i)], 2)
  tags = {
    Name = join("-", [local.mappings["ResourceMap"]["PrivateSubnet"]["Name"], "a"])
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_subnet" "private_subnet_b" {
  availability_zone = "${data.aws_region.current.region}b"
  cidr_block        = element([for __i in range(16) : cidrsubnet(aws_vpc.vpc.cidr_block, 32 - 8 - tonumber(split("/", aws_vpc.vpc.cidr_block)[1]), __i)], 3)
  tags = {
    Name = join("-", [local.mappings["ResourceMap"]["PrivateSubnet"]["Name"], "b"])
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_internet_gateway" "internet_gateway" {
  tags = {
    Name = local.mappings["ResourceMap"]["InternetGateway"]["Name"]
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
    Name = join("-", [local.mappings["ResourceMap"]["NatGateway"]["Name"], "a"])
  }
}
resource "aws_eip" "nat_gateway_b_elastic_ip" {}
resource "aws_nat_gateway" "nat_gateway_b" {
  allocation_id = aws_eip.nat_gateway_b_elastic_ip.allocation_id
  subnet_id     = aws_subnet.public_subnet_b.id
  tags = {
    Name = join("-", [local.mappings["ResourceMap"]["NatGateway"]["Name"], "b"])
  }
}
resource "aws_route_table" "public_subnet_route_table" {
  tags = {
    Name = join("-", [local.mappings["ResourceMap"]["PublicSubnet"]["Name"], "rt"])
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_route_table_association" "public_subnet_a_route_table_association" {
  route_table_id = aws_route_table.public_subnet_route_table.id
  subnet_id      = aws_subnet.public_subnet_a.id
}
resource "aws_route_table_association" "public_subnet_b_route_table_association" {
  route_table_id = aws_route_table.public_subnet_route_table.id
  subnet_id      = aws_subnet.public_subnet_b.id
}
resource "aws_route" "public_subnet_route" {
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.internet_gateway.id
  route_table_id         = aws_route_table.public_subnet_route_table.id
}
resource "aws_route_table" "private_subnet_a_route_table" {
  tags = {
    Name = join("-", [local.mappings["ResourceMap"]["PrivateSubnet"]["Name"], "a", "rt"])
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
    Name = join("-", [local.mappings["ResourceMap"]["PrivateSubnet"]["Name"], "b", "rt"])
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
resource "aws_lb" "application_load_balancer" {
  ip_address_type    = "ipv4"
  name               = "stem-alb"
  security_groups    = [aws_security_group.application_load_balancer_security_group.id]
  subnets            = [aws_subnet.public_subnet_a.id, aws_subnet.public_subnet_b.id]
  load_balancer_type = "application"
  internal           = false
}
resource "aws_security_group" "application_load_balancer_security_group" {
  description = "Security Group for Application Load Balancer"
  name        = "alb-sg"
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
    target_group_arn = aws_lb_target_group.target_group1.arn
    type             = "forward"
  }
  load_balancer_arn = aws_lb.application_load_balancer.arn
  port              = 80
  protocol          = "HTTP"
}
resource "aws_lb_listener_rule" "listener_rule" {
  action {
    type = "forward"
    forward {
      target_group {
        arn    = aws_lb_target_group.target_group1.arn
        weight = 1
      }
    }
  }
  condition {
    http_header {
      http_header_name = "User-Agent"
      values           = ["Mozilla"]
    }
  }
  listener_arn = aws_lb_listener.listener.arn
  priority     = 1
}
resource "aws_lb_target_group" "target_group1" {
  ip_address_type = "ipv4"
  name            = "stem-tg1"
  port            = 80
  protocol        = "HTTP"
  target_type     = "ip"
  vpc_id          = aws_vpc.vpc.id
  health_check {
    path                = "/health"
    protocol            = "HTTP"
    port                = 80
    interval            = 10
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 4
    enabled             = true
    matcher             = 200
  }
}
resource "aws_lb_target_group" "target_group2" {
  ip_address_type = "ipv4"
  name            = "stem-tg2"
  port            = 80
  protocol        = "HTTP"
  target_type     = "ip"
  vpc_id          = aws_vpc.vpc.id
  health_check {
    path                = "/health"
    protocol            = "HTTP"
    port                = 80
    interval            = 10
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 4
    enabled             = true
    matcher             = 200
  }
}
resource "aws_ecr_repository" "ecr" {
  force_delete = true
  name         = "stem-ecr"
}
# CreationPolicy: CloudFormation CreationPolicy (cfn-signal) has no Terraform equivalent; the wait is not reproduced.
# # {
# #   "ResourceSignal": {
# #     "Count": "1",
# #     "Timeout": "PT15M"
# #   }
# # }
resource "aws_instance" "bastion_ec2" {
  ami           = local.mappings["RegionMap"][data.aws_region.current.region]["AmazonLinux2023"]
  instance_type = local.mappings["ResourceMap"]["BastionEc2"]["InstanceType"]
  key_name      = aws_key_pair.key_pair.key_name
  tags = {
    Name = local.mappings["ResourceMap"]["BastionEc2"]["Name"]
  }
  iam_instance_profile        = aws_iam_instance_profile.bastion_ec2_instance_profile.name
  user_data                   = <<EOT
#!/bin/bash -xe
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
dnf update -y
dnf install docker -y
systemctl start docker
systemctl enable docker
usermod -aG docker ec2-user
newgrp docker
echo 'package main

import (
    "fmt"
    "net/http"
)

func health(w http.ResponseWriter, req *http.Request) {
    fmt.Fprint(w, "OK")
}

func dummy(w http.ResponseWriter, req *http.Request) {
    fmt.Fprint(w, "BLUE")
}

func main() {
    http.HandleFunc("/health", health)
    http.HandleFunc("/v1/dummy", dummy)
    http.ListenAndServe(":80", nil)
}' > main.go
echo 'FROM golang:1.16
WORKDIR /app
COPY main.go .
RUN go build main.go
EXPOSE 80
CMD ["./main"]' > Dockerfile
zip src.zip main.go
aws s3 cp src.zip s3://${aws_s3_bucket.code_pipeline_source_s3_bucket.id}
aws ecr get-login-password --region ${data.aws_region.current.region} | docker login --username AWS --password-stdin ${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.region}.amazonaws.com
IMAGE_TAG=${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.region}.amazonaws.com/${aws_ecr_repository.ecr.name}:prototype
docker build -t $IMAGE_TAG .
docker push $IMAGE_TAG
/opt/aws/bin/cfn-signal -e $? --stack ${var.stack_name} --resource BastionEc2 --region ${data.aws_region.current.region}
EOT
  subnet_id                   = aws_subnet.public_subnet_a.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.bastion_ec2_security_group.id]
  depends_on                  = [aws_ecr_repository.ecr, aws_s3_bucket.code_pipeline_source_s3_bucket]
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
  name = "Ec2AdminRole"
}
resource "aws_iam_instance_profile" "bastion_ec2_instance_profile" {
  name = "Ec2AdminProfile"
  role = jsonencode([aws_iam_role.bastion_ec2_iam_role.name])
}
resource "aws_eip" "bastion_ec2_elastic_ip" {
  instance = aws_instance.bastion_ec2.id
}
resource "aws_iam_role" "ecs_auto_scaling_group_iam_role" {
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
  name = "EcsAutoScalingGroupIamRole"
}
resource "aws_iam_instance_profile" "ecs_auto_scaling_group_profile" {
  name = "EcsAutoScalingGroupProfile"
  role = jsonencode([aws_iam_role.ecs_auto_scaling_group_iam_role.name])
}
resource "aws_ecs_cluster" "ecs_cluster" {
  name = "stem-cluster"
  setting {
    name  = "containerInsights"
    value = "disabled"
  }
  configuration {
    execute_command_configuration {
      logging = "DEFAULT"
    }
  }
}
resource "aws_launch_template" "ecs_launch_template" {
  image_id = local.mappings["RegionMap"][data.aws_region.current.region]["EcsOptimizedAmazonLinux2023"]
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "ecs-asg-instance"
    }
  }
  network_interfaces {
    device_index          = 0
    delete_on_termination = true
    security_groups       = [aws_security_group.ecs_auto_scaling_group_security_group.id]
  }
  key_name = aws_key_pair.key_pair.key_name
  iam_instance_profile {
    arn = aws_iam_instance_profile.ecs_auto_scaling_group_profile.arn
  }
  user_data = base64encode(<<EOT
#!/bin/bash -xe
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
mkdir -p /etc/ecs
echo "ECS_CLUSTER=stem-cluster" > /etc/ecs/ecs.config
EOT
  )
  depends_on = [aws_ecs_cluster.ecs_cluster]
}
resource "aws_autoscaling_group" "ecs_auto_scaling_group" {
  min_size         = 1
  max_size         = 8
  desired_capacity = 2
  default_cooldown = 0
  mixed_instances_policy {
    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.ecs_launch_template.id
        version            = aws_launch_template.ecs_launch_template.latest_version
      }
      override {
        instance_type = "t3.micro"
      }
    }
    instances_distribution {
      on_demand_base_capacity                  = 0
      on_demand_percentage_above_base_capacity = 0
      spot_allocation_strategy                 = "price-capacity-optimized"
    }
  }
  vpc_zone_identifier = [aws_subnet.private_subnet_a.id, aws_subnet.private_subnet_b.id]
  depends_on          = [aws_ecs_cluster.ecs_cluster]
}
resource "aws_security_group" "ecs_auto_scaling_group_security_group" {
  description = "Security Group for ASG"
  name        = "asg-sg"
  vpc_id      = aws_vpc.vpc.id
  ingress {
    from_port       = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_ec2_security_group.id]
    to_port         = 22
  }
}
resource "aws_ecs_capacity_provider" "ecs_capacity_provider" {
  name = "CapacityProvider"
  auto_scaling_group_provider {
    auto_scaling_group_arn = aws_autoscaling_group.ecs_auto_scaling_group.name
    managed_scaling {
      instance_warmup_period = 60
      status                 = "ENABLED"
      target_capacity        = 100
    }
    managed_termination_protection = "DISABLED"
  }
}
resource "aws_ecs_cluster_capacity_providers" "cluster_cp_association" {
  cluster_name       = aws_ecs_cluster.ecs_cluster.name
  capacity_providers = [aws_ecs_capacity_provider.ecs_capacity_provider.id]
  default_capacity_provider_strategy {
    base              = 0
    weight            = 1
    capacity_provider = aws_ecs_capacity_provider.ecs_capacity_provider.id
  }
  depends_on = [aws_ecs_cluster.ecs_cluster]
}
resource "aws_iam_role" "ecs_task_execution_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = ""
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}
resource "aws_ecs_task_definition" "ecs_task_definition" {
  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn
  container_definitions = jsonencode([{
    Name      = "golang-app"
    Image     = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.region}.amazonaws.com/${aws_ecr_repository.ecr.name}:prototype"
    Essential = true
    PortMappings = [{
      HostPort      = 80
      Protocol      = "tcp"
      ContainerPort = 80
    }]
    HealthCheck = {
      Command = ["CMD-SHELL", "curl -f http://localhost/health || exit 1"]
    }
  }])
  network_mode = "awsvpc"
  cpu          = "256"
  memory       = "512"
  family       = "stem-td"
  depends_on   = [aws_instance.bastion_ec2]
}
resource "aws_security_group" "ecs_security_group" {
  description = "Security Group for ECS"
  name        = "stem-ecs-sg"
  vpc_id      = aws_vpc.vpc.id
  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.application_load_balancer_security_group.id]
  }
  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.application_load_balancer_security_group.id]
  }
}
resource "aws_cloudwatch_log_group" "ecs_task_cloud_watch_log_group" {
  name = "/ecs/stem-td"
}
resource "aws_ecs_service" "ecs_service" {
  cluster             = "stem-cluster"
  task_definition     = aws_ecs_task_definition.ecs_task_definition.arn
  name                = "stem-svc"
  scheduling_strategy = "REPLICA"
  desired_count       = 2
  load_balancer {
    container_name   = "golang-app"
    container_port   = 80
    target_group_arn = aws_lb_target_group.target_group1.arn
  }
  network_configuration {
    security_groups = [aws_security_group.ecs_security_group.id]
    subnets         = [aws_subnet.private_subnet_a.id, aws_subnet.private_subnet_b.id]
  }
  deployment_controller {
    type = "CODE_DEPLOY"
  }
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
  depends_on = [aws_lb_listener.listener, aws_cloudwatch_log_group.ecs_task_cloud_watch_log_group]
}
resource "aws_s3_bucket" "code_pipeline_source_s3_bucket" {}
resource "aws_codebuild_project" "code_build" {
  artifacts {
    type = "CODEPIPELINE"
  }
  environment {
    compute_type = "BUILD_GENERAL1_MEDIUM"
    type         = "LINUX_CONTAINER"
    image        = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
  }
  name         = local.mappings["ResourceMap"]["CodePipeline"]["Build"]
  service_role = aws_iam_role.code_build_iam_role.name
  source {
    buildspec = <<EOT
version: 0.2
env:
  variables:
    AWS_DEFAULT_REGION: ${data.aws_region.current.region}
    AWS_ACCOUNT_ID: ${data.aws_caller_identity.current.account_id}
    IMAGE_REPO_NAME: ${aws_ecr_repository.ecr.name}
    CAPACITY_PROVIDER: ${aws_ecs_capacity_provider.ecs_capacity_provider.id}
phases:
  pre_build:
    commands:
      - ln -sf /usr/share/zoneinfo/Asia/Seoul /etc/localtime
      # - |
      #   echo 'package main
      #   import (
      #       "fmt"
      #       "net/http"
      #   )
      #   func health(w http.ResponseWriter, req *http.Request) {
      #       fmt.Fprint(w, "OK")
      #   }
      #   func dummy(w http.ResponseWriter, req *http.Request) {
      #       fmt.Fprint(w, "BLUE")
      #   }
      #   func main() {
      #       http.HandleFunc("/health", health)
      #       http.HandleFunc("/v1/dummy", dummy)
      #       http.ListenAndServe(":80", nil)
      #   }' > main.go
      - |
        echo 'FROM golang:1.16
        WORKDIR /app
        COPY . .
        RUN go build main.go
        EXPOSE 80
        CMD ["./main"]' > Dockerfile
  build:
    commands:
      - IMAGE_VERSION=$(LC_TIME=ko_KR.UTF-8 date +'%Y-%m-%d.%H.%M.%S')
      - IMAGE_TAG=$AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com/$IMAGE_REPO_NAME:$IMAGE_VERSION
      # Enable DockerHub Login if you meet the error "toomanyrequests"
      # - DOCKERHUB_USERNAME=
      # - DOCKERHUB_PASSWORD=
      # - echo "$DOCKERHUB_PASSWORD" | docker login -u "$DOCKERHUB_USERNAME" --password-stdin
      - docker build -t $IMAGE_TAG .
      - aws ecr get-login-password --region $AWS_DEFAULT_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com
      - docker push $IMAGE_TAG
  post_build:
    commands:
      - IMAGE_VERSION=$(echo $(aws ecr describe-images --repository-name $IMAGE_REPO_NAME --query 'sort_by(imageDetails,& imagePushedAt)[-1].imageTags[0]') | tr -d '"')
      - FAMILY="stem-td"
      - EXECUTION_ROLE_ARN="arn:aws:iam::$AWS_ACCOUNT_ID:role/${aws_iam_role.ecs_task_execution_role.name}"
      - CONTAINER_NAME="golang-app"
      - CONTAINER_PORT="80"
      - CONTAINER_IMAGE="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com/$IMAGE_REPO_NAME:$IMAGE_VERSION"
      - |
        jq -n --arg FAMILY $FAMILY --arg EXECUTION_ROLE_ARN $EXECUTION_ROLE_ARN --arg CONTAINER_NAME $CONTAINER_NAME --arg CONTAINER_IMAGE $CONTAINER_IMAGE --arg AWS_DEFAULT_REGION $AWS_DEFAULT_REGION \
          '{ "family":$FAMILY, "executionRoleArn":$EXECUTION_ROLE_ARN, "networkMode":"awsvpc", "cpu":"256", "memory":"512", "containerDefinitions":[{"healthCheck":{"command":["CMD-SHELL","curl -f http://localhost/health || exit 1"],"interval":10,"timeout":5,"retries":3,"startPeriod": 0},"logConfiguration":{"logDriver":"awslogs","options":{"awslogs-group":"/ecs/stem-td","awslogs-region":$AWS_DEFAULT_REGION,"awslogs-stream-prefix":"ecs"}},"name":$CONTAINER_NAME,"image":$CONTAINER_IMAGE,"portMappings":[{"containerPort":80,"hostPort":80,"protocol":"tcp"}]}] }' \
          > task-definition.json
      - TASK_DEFINITION_JSON=$(aws ecs register-task-definition --cli-input-json file://task-definition.json)
      - TASK_DEFINITION_ARN=$(echo $TASK_DEFINITION_JSON | jq -r '.taskDefinition .taskDefinitionArn')
      - >
        jq -n --arg TASK_DEFINITION_ARN $TASK_DEFINITION_ARN --arg CONTAINER_NAME $CONTAINER_NAME --arg CONTAINER_PORT $CONTAINER_PORT --arg CAPACITY_PROVIDER $CAPACITY_PROVIDER \
        '{"version": 0.0, "Resources": [{"TargetService": {"Type": "AWS::ECS::Service", "Properties": {"TaskDefinition": $TASK_DEFINITION_ARN, "LoadBalancerInfo": {"ContainerName": $CONTAINER_NAME, "ContainerPort": $CONTAINER_PORT}, "CapacityProviderStrategy": [{"Base":0,"CapacityProvider":$CAPACITY_PROVIDER,"Weight":1}]}}}]}' \
        > appspec.json
artifacts:
  files:
    - appspec.json
  discard-paths: yes
EOT
    type      = "CODEPIPELINE"
  }
  build_timeout = 15
}
resource "aws_iam_role" "code_build_iam_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["codebuild.amazonaws.com"]
      }
      Action = ["sts:AssumeRole"]
    }]
  })
  name = "CodeBuildRole"
}
resource "aws_codedeploy_app" "code_deploy_application" {
  name             = local.mappings["ResourceMap"]["CodePipeline"]["DeployApplication"]
  compute_platform = "ECS"
}
resource "aws_codedeploy_deployment_group" "code_deploy_deployment_group" {
  app_name = aws_codedeploy_app.code_deploy_application.name
  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM", "DEPLOYMENT_STOP_ON_REQUEST"]
  }
  deployment_group_name  = local.mappings["ResourceMap"]["CodePipeline"]["DeploymentGroup"]
  service_role_arn       = aws_iam_role.code_deploy_iam_role.arn
  deployment_config_name = "CodeDeployDefault.ECSAllAtOnce"
  deployment_style {
    deployment_option = "WITH_TRAFFIC_CONTROL"
    deployment_type   = "BLUE_GREEN"
  }
  ecs_service {
    cluster_name = aws_ecs_cluster.ecs_cluster.name
    service_name = aws_ecs_service.ecs_service.name
  }
  load_balancer_info {
    target_group_pair_info {
      prod_traffic_route {
        listener_arns = [aws_lb_listener.listener.arn]
      }
      target_group {
        name = aws_lb_target_group.target_group1.name
      }
      target_group {
        name = aws_lb_target_group.target_group2.name
      }
    }
  }
  blue_green_deployment_config {
    deployment_ready_option {
      action_on_timeout = "CONTINUE_DEPLOYMENT"
    }
    terminate_blue_instances_on_deployment_success {
      action                           = "TERMINATE"
      termination_wait_time_in_minutes = 0
    }
  }
  depends_on = [aws_ecs_service.ecs_service]
}
resource "aws_iam_role" "code_deploy_iam_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["codedeploy.amazonaws.com"]
      }
      Action = ["sts:AssumeRole"]
    }]
  })
  name = "CodeDeployRole"
}
resource "aws_codepipeline" "code_pipeline" {
  name          = local.mappings["ResourceMap"]["CodePipeline"]["Name"]
  pipeline_type = "V2"
  artifact_store {
    location = aws_s3_bucket.code_pipeline_artifact_store_s3_bucket.id
    type     = "S3"
  }
  role_arn = aws_iam_role.code_pipeline_iam_role.arn
  stage {
    name = "SourceStage"
    action {
      name = "SourceAction"
      configuration = {
        S3Bucket             = aws_s3_bucket.code_pipeline_source_s3_bucket.id
        S3ObjectKey          = "src.zip"
        PollForSourceChanges = "false"
      }
      output_artifacts = ["SourceOutput"]
      category         = "Source"
      owner            = "AWS"
      provider         = "S3"
      version          = 1
    }
  }
  stage {
    name = "BuildStage"
    action {
      name = "BuildAction"
      configuration = {
        ProjectName = aws_codebuild_project.code_build.name
      }
      input_artifacts  = ["SourceOutput"]
      output_artifacts = ["BuildOutput"]
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = 1
    }
  }
  stage {
    name = "DeployStage"
    action {
      name = "DeployAction"
      configuration = {
        ApplicationName     = aws_codedeploy_app.code_deploy_application.name
        DeploymentGroupName = aws_codedeploy_deployment_group.code_deploy_deployment_group.id
      }
      input_artifacts = ["BuildOutput"]
      category        = "Deploy"
      owner           = "AWS"
      provider        = "CodeDeploy"
      version         = 1
    }
  }
}
resource "aws_s3_bucket" "code_pipeline_artifact_store_s3_bucket" {}
resource "aws_iam_role" "code_pipeline_iam_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["codepipeline.amazonaws.com"]
      }
      Action = ["sts:AssumeRole"]
    }]
  })
  name = "CodePipelineRole"
}
resource "aws_cloudwatch_event_rule" "cloud_watch_event_rule" {
  description    = "CodePipeline Source Stage에서 변경이 발생하면 파이프라인을 자동으로 시작하는 Amazon CloudWatch Events 규칙입니다. 이 규칙을 삭제하면 해당 파이프라인에서 변경 사항이 감지되지 않습니다. 자세한 정보: http://docs.aws.amazon.com/codepipeline/latest/userguide/pipelines-about-starting.html"
  event_bus_name = "default"
  event_pattern = jsonencode({
    source        = ["aws.s3"]
    "detail-type" = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource = ["s3.amazonaws.com"]
      eventName   = ["CopyObject", "PutObject", "CompleteMultipartUpload"]
      requestParameters = {
        bucketName = [aws_s3_bucket.code_pipeline_source_s3_bucket.id]
        key        = ["src.zip"]
      }
    }
  })
  name  = "codepipeline-event-rule"
  state = "ENABLED"
}
resource "aws_iam_role" "cloud_watch_event_rule_iam_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["events.amazonaws.com"]
      }
      Action = ["sts:AssumeRole"]
    }]
  })
  name = "CloudWatchEventRuleRole"
}
resource "aws_cloudtrail" "cloud_trail" {
  name = local.mappings["ResourceMap"]["CodePipeline"]["CloudTrail"]
  event_selector {
    data_resource {
      type   = "AWS::S3::Object"
      values = ["${aws_s3_bucket.code_pipeline_source_s3_bucket.arn}/src.zip"]
    }
    read_write_type = "WriteOnly"
  }
  enable_logging = true
  s3_bucket_name = aws_s3_bucket.cloud_trail_logs_bucket.id
  depends_on     = [aws_s3_bucket.cloud_trail_logs_bucket, aws_s3_bucket_policy.cloud_trail_logs_bucket_policy]
}
resource "aws_s3_bucket" "cloud_trail_logs_bucket" {}
resource "aws_s3_bucket_policy" "cloud_trail_logs_bucket_policy" {
  bucket = aws_s3_bucket.cloud_trail_logs_bucket.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action   = ["s3:GetBucketAcl"]
      Effect   = "Allow"
      Resource = aws_s3_bucket.cloud_trail_logs_bucket.arn
      Principal = {
        Service = "cloudtrail.amazonaws.com"
      }
      Condition = {
        StringEquals = {
          "aws:SourceArn" = "arn:aws:cloudtrail:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:trail/${local.mappings["ResourceMap"]["CodePipeline"]["CloudTrail"]}"
        }
      }
      }, {
      Action   = ["s3:PutObject"]
      Effect   = "Allow"
      Resource = "${aws_s3_bucket.cloud_trail_logs_bucket.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
      Principal = {
        Service = "cloudtrail.amazonaws.com"
      }
      Condition = {
        StringEquals = {
          "s3:x-amz-acl"  = "bucket-owner-full-control"
          "aws:SourceArn" = "arn:aws:cloudtrail:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:trail/${local.mappings["ResourceMap"]["CodePipeline"]["CloudTrail"]}"
        }
      }
    }]
  })
}
