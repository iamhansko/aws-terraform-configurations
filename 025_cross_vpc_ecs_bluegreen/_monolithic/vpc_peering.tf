# Generated from 025_cross_vpc_ecs_bluegreen/vpc_peering.yaml by tools/cfn2tf.
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
  default     = "vpc-peering"
  description = "Stands in for AWS::StackName."
}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}
# Provides the unique suffix that AWS::StackId supplies in CloudFormation.
resource "random_uuid" "stack_id" {}
# --- Parameters ---
variable "random_number" {
  type = string
}
variable "vpc_a_name" {
  type    = string
  default = "ws25-hub-vpc"
}
variable "vpc_a_cidr" {
  type    = string
  default = "172.28.0.0/16"
}
variable "vpc_b_name" {
  type    = string
  default = "ws25-app-vpc"
}
variable "vpc_b_cidr" {
  type    = string
  default = "10.200.0.0/16"
}
variable "vpc_a_pub_subnet_a_name" {
  type    = string
  default = "ws25-hub-pub-a"
}
variable "vpc_a_pub_subnet_a_cidr" {
  type    = string
  default = "172.28.0.0/20"
}
variable "vpc_a_pub_subnet_c_name" {
  type    = string
  default = "ws25-hub-pub-c"
}
variable "vpc_a_pub_subnet_c_cidr" {
  type    = string
  default = "172.28.16.0/20"
}
variable "vpc_b_pub_subnet_a_name" {
  type    = string
  default = "ws25-app-pub-a"
}
variable "vpc_b_pub_subnet_a_cidr" {
  type    = string
  default = "10.200.10.0/24"
}
variable "vpc_b_pub_subnet_b_name" {
  type    = string
  default = "ws25-app-pub-b"
}
variable "vpc_b_pub_subnet_b_cidr" {
  type    = string
  default = "10.200.11.0/24"
}
variable "vpc_b_pub_subnet_c_name" {
  type    = string
  default = "ws25-app-pub-c"
}
variable "vpc_b_pub_subnet_c_cidr" {
  type    = string
  default = "10.200.12.0/24"
}
variable "vpc_b_priv_subnet_a_name" {
  type    = string
  default = "ws25-app-pri-a"
}
variable "vpc_b_priv_subnet_a_cidr" {
  type    = string
  default = "10.200.20.0/24"
}
variable "vpc_b_priv_subnet_b_name" {
  type    = string
  default = "ws25-app-pri-b"
}
variable "vpc_b_priv_subnet_b_cidr" {
  type    = string
  default = "10.200.21.0/24"
}
variable "vpc_b_priv_subnet_c_name" {
  type    = string
  default = "ws25-app-pri-c"
}
variable "vpc_b_priv_subnet_c_cidr" {
  type    = string
  default = "10.200.22.0/24"
}
variable "vpc_b_internal_subnet_a_name" {
  type    = string
  default = "ws25-app-db-a"
}
variable "vpc_b_internal_subnet_a_cidr" {
  type    = string
  default = "10.200.30.0/24"
}
variable "vpc_b_internal_subnet_c_name" {
  type    = string
  default = "ws25-app-db-c"
}
variable "vpc_b_internal_subnet_c_cidr" {
  type    = string
  default = "10.200.31.0/24"
}
variable "vpc_a_pub_rt_name" {
  type    = string
  default = "ws25-hub-pub-rt"
}
variable "vpc_a_igw_name" {
  type    = string
  default = "ws25-hub-igw"
}
variable "vpc_b_pub_rt_name" {
  type    = string
  default = "ws25-app-pub-rt"
}
variable "vpc_b_igw_name" {
  type    = string
  default = "ws25-app-igw"
}
variable "vpc_b_priv_a_rt_name" {
  type    = string
  default = "ws25-app-pri-rt-a"
}
variable "vpc_b_natgw_a_name" {
  type    = string
  default = "ws25-app-ngw-a"
}
variable "vpc_b_priv_b_rt_name" {
  type    = string
  default = "ws25-app-pri-rt-b"
}
variable "vpc_b_natgw_b_name" {
  type    = string
  default = "ws25-app-ngw-b"
}
variable "vpc_b_priv_c_rt_name" {
  type    = string
  default = "ws25-app-pri-rt-c"
}
variable "vpc_b_natgw_c_name" {
  type    = string
  default = "ws25-app-ngw-c"
}
variable "vpc_b_internal_a_rt_name" {
  type    = string
  default = "ws25-app-db-rt-a"
}
variable "vpc_b_internal_c_rt_name" {
  type    = string
  default = "ws25-app-db-rt-c"
}
variable "vpc_peering_name" {
  type    = string
  default = "ws25-peering"
}
variable "bastion_ec2_ami_id" {
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
  description = "(SSM parameter path; resolved by the aws_ssm_parameter data source)"
}
data "aws_ssm_parameter" "bastion_ec2_ami_id" {
  name = var.bastion_ec2_ami_id
}
variable "rds_username" {
  type    = string
  default = "admin"
}
variable "rds_password" {
  type      = string
  default   = "dbpassword"
  sensitive = true
}
variable "rds_database" {
  type    = string
  default = "day1"
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
resource "aws_iam_role_policy" "vpc_a_iam_role" {
  name = "CloudWatchLogsPolicy"
  role = aws_iam_role.vpc_a_iam_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogGroups", "logs:DescribeLogStreams"]
      Resource = "*"
    }]
  })
}
resource "aws_iam_role_policy" "vpc_b_iam_role" {
  name = "CloudWatchLogsPolicy"
  role = aws_iam_role.vpc_b_iam_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogGroups", "logs:DescribeLogStreams"]
      Resource = "*"
    }]
  })
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
resource "aws_secretsmanager_secret_version" "rds_secret" {
  secret_id     = aws_secretsmanager_secret.rds_secret.id
  secret_string = "{\"DB_URL\":\"${aws_rds_cluster.rds_cluster.endpoint}:10101\",\"DB_USER\":\"${var.rds_username}\",\"DB_PASSWD\":\"${var.rds_password}\"}"
}
resource "aws_iam_role_policy_attachment" "rds_enhanced_monitoring_iam_role" {
  role       = aws_iam_role.rds_enhanced_monitoring_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
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
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}
resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_0" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_1" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/SecretsManagerReadWrite"
}
resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_2" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}
resource "aws_lb_target_group_attachment" "app_nlb_target_group" {
  target_group_arn = aws_lb_target_group.app_nlb_target_group.arn
  target_id        = aws_lb.app_alb.arn
  port             = 80
}
resource "aws_s3_bucket_versioning" "green_source_s3_bucket_versioning" {
  bucket = aws_s3_bucket.green_source_s3_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}
resource "aws_s3_bucket_versioning" "red_source_s3_bucket_versioning" {
  bucket = aws_s3_bucket.red_source_s3_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}
resource "aws_iam_role_policy_attachment" "code_deploy_iam_role" {
  role       = aws_iam_role.code_deploy_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodeDeployRoleForECS"
}
resource "aws_iam_role_policy" "code_pipeline_iam_role" {
  name = "CodePipelinePolicy"
  role = aws_iam_role.code_pipeline_iam_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["codepipeline:StartPipelineExecution", "s3:*", "codebuild:*", "codedeploy:*", "ecs:RegisterTaskDefinition", "iam:PassRole"]
      Resource = "*"
    }]
  })
}
resource "aws_cloudwatch_event_target" "green_cloud_watch_event_rule" {
  rule      = aws_cloudwatch_event_rule.green_cloud_watch_event_rule.name
  arn       = "arn:aws:codepipeline:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:ws25-cd-green-pipeline"
  target_id = "green-codepipeline"
  role_arn  = aws_iam_role.cloud_watch_event_rule_iam_role.arn
}
resource "aws_cloudwatch_event_target" "red_cloud_watch_event_rule" {
  rule      = aws_cloudwatch_event_rule.red_cloud_watch_event_rule.name
  arn       = "arn:aws:codepipeline:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:ws25-cd-red-pipeline"
  target_id = "red-codepipeline"
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
      Resource = "*"
    }]
  })
}
# --- Resources ---
resource "aws_vpc" "vpc_a" {
  cidr_block           = var.vpc_a_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = var.vpc_a_name
  }
}
resource "aws_vpc" "vpc_b" {
  cidr_block           = var.vpc_b_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = var.vpc_b_name
  }
}
resource "aws_internet_gateway" "vpc_a_igw" {
  tags = {
    Name = var.vpc_a_igw_name
  }
}
resource "aws_internet_gateway_attachment" "vpc_a_igw_attachment" {
  internet_gateway_id = aws_internet_gateway.vpc_a_igw.id
  vpc_id              = aws_vpc.vpc_a.id
}
resource "aws_route_table" "vpc_a_public_rt" {
  tags = {
    Name = var.vpc_a_pub_rt_name
  }
  vpc_id = aws_vpc.vpc_a.id
}
resource "aws_route" "vpc_a_public_route" {
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.vpc_a_igw.id
  route_table_id         = aws_route_table.vpc_a_public_rt.id
}
resource "aws_route" "vpc_a_public_peering_route" {
  destination_cidr_block    = aws_vpc.vpc_b.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.vpc_peering_connection.id
  route_table_id            = aws_route_table.vpc_a_public_rt.id
}
resource "aws_subnet" "vpc_a_public_subnet_a" {
  availability_zone       = "${data.aws_region.current.region}a"
  cidr_block              = var.vpc_a_pub_subnet_a_cidr
  map_public_ip_on_launch = true
  tags = {
    Name = var.vpc_a_pub_subnet_a_name
  }
  vpc_id = aws_vpc.vpc_a.id
}
resource "aws_route_table_association" "vpc_a_public_subnet_a_rt_association" {
  route_table_id = aws_route_table.vpc_a_public_rt.id
  subnet_id      = aws_subnet.vpc_a_public_subnet_a.id
}
resource "aws_subnet" "vpc_a_public_subnet_c" {
  availability_zone       = "${data.aws_region.current.region}c"
  cidr_block              = var.vpc_a_pub_subnet_c_cidr
  map_public_ip_on_launch = true
  tags = {
    Name = var.vpc_a_pub_subnet_c_name
  }
  vpc_id = aws_vpc.vpc_a.id
}
resource "aws_route_table_association" "vpc_a_public_subnet_c_rt_association" {
  route_table_id = aws_route_table.vpc_a_public_rt.id
  subnet_id      = aws_subnet.vpc_a_public_subnet_c.id
}
resource "aws_internet_gateway" "vpc_b_igw" {
  tags = {
    Name = var.vpc_b_igw_name
  }
}
resource "aws_internet_gateway_attachment" "vpc_b_igw_attachment" {
  internet_gateway_id = aws_internet_gateway.vpc_b_igw.id
  vpc_id              = aws_vpc.vpc_b.id
}
resource "aws_route_table" "vpc_b_public_rt" {
  tags = {
    Name = var.vpc_b_pub_rt_name
  }
  vpc_id = aws_vpc.vpc_b.id
}
resource "aws_route" "vpc_b_public_route" {
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.vpc_b_igw.id
  route_table_id         = aws_route_table.vpc_b_public_rt.id
}
resource "aws_route" "vpc_b_public_peering_route" {
  destination_cidr_block    = aws_vpc.vpc_a.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.vpc_peering_connection.id
  route_table_id            = aws_route_table.vpc_b_public_rt.id
}
resource "aws_subnet" "vpc_b_public_subnet_a" {
  availability_zone       = "${data.aws_region.current.region}a"
  cidr_block              = var.vpc_b_pub_subnet_a_cidr
  map_public_ip_on_launch = true
  tags = {
    Name = var.vpc_b_pub_subnet_a_name
  }
  vpc_id = aws_vpc.vpc_b.id
}
resource "aws_route_table_association" "vpc_b_public_subnet_a_rt_association" {
  route_table_id = aws_route_table.vpc_b_public_rt.id
  subnet_id      = aws_subnet.vpc_b_public_subnet_a.id
}
resource "aws_subnet" "vpc_b_public_subnet_b" {
  availability_zone       = "${data.aws_region.current.region}b"
  cidr_block              = var.vpc_b_pub_subnet_b_cidr
  map_public_ip_on_launch = true
  tags = {
    Name = var.vpc_b_pub_subnet_b_name
  }
  vpc_id = aws_vpc.vpc_b.id
}
resource "aws_route_table_association" "vpc_b_public_subnet_b_rt_association" {
  route_table_id = aws_route_table.vpc_b_public_rt.id
  subnet_id      = aws_subnet.vpc_b_public_subnet_b.id
}
resource "aws_subnet" "vpc_b_public_subnet_c" {
  availability_zone       = "${data.aws_region.current.region}c"
  cidr_block              = var.vpc_b_pub_subnet_c_cidr
  map_public_ip_on_launch = true
  tags = {
    Name = var.vpc_b_pub_subnet_c_name
  }
  vpc_id = aws_vpc.vpc_b.id
}
resource "aws_route_table_association" "vpc_b_public_subnet_c_rt_association" {
  route_table_id = aws_route_table.vpc_b_public_rt.id
  subnet_id      = aws_subnet.vpc_b_public_subnet_c.id
}
resource "aws_subnet" "vpc_b_private_subnet_a" {
  availability_zone = "${data.aws_region.current.region}a"
  cidr_block        = var.vpc_b_priv_subnet_a_cidr
  tags = {
    Name = var.vpc_b_priv_subnet_a_name
  }
  vpc_id = aws_vpc.vpc_b.id
}
resource "aws_eip" "vpc_b_natgw_a_elastic_ip" {}
resource "aws_nat_gateway" "vpc_b_natgw_a" {
  allocation_id = aws_eip.vpc_b_natgw_a_elastic_ip.allocation_id
  subnet_id     = aws_subnet.vpc_b_public_subnet_a.id
  tags = {
    Name = var.vpc_b_natgw_a_name
  }
}
resource "aws_route_table" "vpc_b_priv_a_rt" {
  tags = {
    Name = var.vpc_b_priv_a_rt_name
  }
  vpc_id = aws_vpc.vpc_b.id
}
resource "aws_route_table_association" "vpc_b_priv_a_rt_association" {
  route_table_id = aws_route_table.vpc_b_priv_a_rt.id
  subnet_id      = aws_subnet.vpc_b_private_subnet_a.id
}
resource "aws_route" "vpc_b_private_subnet_a_route" {
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.vpc_b_natgw_a.id
  route_table_id         = aws_route_table.vpc_b_priv_a_rt.id
}
resource "aws_route" "vpc_b_private_subnet_a_peering_route" {
  destination_cidr_block    = aws_vpc.vpc_a.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.vpc_peering_connection.id
  route_table_id            = aws_route_table.vpc_b_priv_a_rt.id
}
resource "aws_subnet" "vpc_b_private_subnet_b" {
  availability_zone = "${data.aws_region.current.region}b"
  cidr_block        = var.vpc_b_priv_subnet_b_cidr
  tags = {
    Name = var.vpc_b_priv_subnet_b_name
  }
  vpc_id = aws_vpc.vpc_b.id
}
resource "aws_eip" "vpc_b_natgw_b_elastic_ip" {}
resource "aws_nat_gateway" "vpc_b_natgw_b" {
  allocation_id = aws_eip.vpc_b_natgw_b_elastic_ip.allocation_id
  subnet_id     = aws_subnet.vpc_b_public_subnet_b.id
  tags = {
    Name = var.vpc_b_natgw_b_name
  }
}
resource "aws_route_table" "vpc_b_priv_b_rt" {
  tags = {
    Name = var.vpc_b_priv_b_rt_name
  }
  vpc_id = aws_vpc.vpc_b.id
}
resource "aws_route_table_association" "vpc_b_priv_b_rt_association" {
  route_table_id = aws_route_table.vpc_b_priv_b_rt.id
  subnet_id      = aws_subnet.vpc_b_private_subnet_b.id
}
resource "aws_route" "vpc_b_private_subnet_b_route" {
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.vpc_b_natgw_b.id
  route_table_id         = aws_route_table.vpc_b_priv_b_rt.id
}
resource "aws_route" "vpc_b_private_subnet_b_peering_route" {
  destination_cidr_block    = aws_vpc.vpc_a.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.vpc_peering_connection.id
  route_table_id            = aws_route_table.vpc_b_priv_b_rt.id
}
resource "aws_subnet" "vpc_b_private_subnet_c" {
  availability_zone = "${data.aws_region.current.region}c"
  cidr_block        = var.vpc_b_priv_subnet_c_cidr
  tags = {
    Name = var.vpc_b_priv_subnet_c_name
  }
  vpc_id = aws_vpc.vpc_b.id
}
resource "aws_eip" "vpc_b_natgw_c_elastic_ip" {}
resource "aws_nat_gateway" "vpc_b_natgw_c" {
  allocation_id = aws_eip.vpc_b_natgw_c_elastic_ip.allocation_id
  subnet_id     = aws_subnet.vpc_b_public_subnet_c.id
  tags = {
    Name = var.vpc_b_natgw_c_name
  }
}
resource "aws_route_table" "vpc_b_priv_c_rt" {
  tags = {
    Name = var.vpc_b_priv_c_rt_name
  }
  vpc_id = aws_vpc.vpc_b.id
}
resource "aws_route_table_association" "vpc_b_priv_c_rt_association" {
  route_table_id = aws_route_table.vpc_b_priv_c_rt.id
  subnet_id      = aws_subnet.vpc_b_private_subnet_c.id
}
resource "aws_route" "vpc_b_private_subnet_c_route" {
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.vpc_b_natgw_c.id
  route_table_id         = aws_route_table.vpc_b_priv_c_rt.id
}
resource "aws_route" "vpc_b_private_subnet_c_peering_route" {
  destination_cidr_block    = aws_vpc.vpc_a.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.vpc_peering_connection.id
  route_table_id            = aws_route_table.vpc_b_priv_c_rt.id
}
resource "aws_subnet" "vpc_b_internal_subnet_a" {
  availability_zone = "${data.aws_region.current.region}a"
  cidr_block        = var.vpc_b_internal_subnet_a_cidr
  tags = {
    Name = var.vpc_b_internal_subnet_a_name
  }
  vpc_id = aws_vpc.vpc_b.id
}
resource "aws_route_table" "vpc_b_internal_a_rt" {
  tags = {
    Name = var.vpc_b_internal_a_rt_name
  }
  vpc_id = aws_vpc.vpc_b.id
}
resource "aws_route_table_association" "vpc_b_internal_a_rt_association" {
  route_table_id = aws_route_table.vpc_b_internal_a_rt.id
  subnet_id      = aws_subnet.vpc_b_internal_subnet_a.id
}
resource "aws_route" "vpc_b_internal_subnet_a_peering_route" {
  destination_cidr_block    = aws_vpc.vpc_a.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.vpc_peering_connection.id
  route_table_id            = aws_route_table.vpc_b_internal_a_rt.id
}
resource "aws_subnet" "vpc_b_internal_subnet_c" {
  availability_zone = "${data.aws_region.current.region}c"
  cidr_block        = var.vpc_b_internal_subnet_c_cidr
  tags = {
    Name = var.vpc_b_internal_subnet_c_name
  }
  vpc_id = aws_vpc.vpc_b.id
}
resource "aws_route_table" "vpc_b_internal_c_rt" {
  tags = {
    Name = var.vpc_b_internal_c_rt_name
  }
  vpc_id = aws_vpc.vpc_b.id
}
resource "aws_route_table_association" "vpc_b_internal_c_rt_association" {
  route_table_id = aws_route_table.vpc_b_internal_c_rt.id
  subnet_id      = aws_subnet.vpc_b_internal_subnet_c.id
}
resource "aws_route" "vpc_b_internal_subnet_c_peering_route" {
  destination_cidr_block    = aws_vpc.vpc_a.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.vpc_peering_connection.id
  route_table_id            = aws_route_table.vpc_b_internal_c_rt.id
}
resource "aws_vpc_peering_connection" "vpc_peering_connection" {
  vpc_id      = aws_vpc.vpc_a.id
  peer_vpc_id = aws_vpc.vpc_b.id
  tags = {
    Name = var.vpc_peering_name
  }
}
resource "aws_flow_log" "vpc_a_flow_log" {
  iam_role_arn             = aws_iam_role.vpc_a_iam_role.arn
  log_destination_type     = "cloud-watch-logs"
  max_aggregation_interval = 600
  tags = {
    Name = "vpc-a-flow-log"
  }
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.vpc_a.id
  log_destination = "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/ws25/flow/hub"
}
resource "aws_iam_role" "vpc_a_iam_role" {
  name = "VpcAFlowLogIamRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["sts:AssumeRole"]
      Principal = {
        Service = ["vpc-flow-logs.amazonaws.com"]
      }
    }]
  })
}
resource "aws_flow_log" "vpc_b_flow_log" {
  iam_role_arn             = aws_iam_role.vpc_b_iam_role.arn
  log_destination_type     = "cloud-watch-logs"
  max_aggregation_interval = 600
  tags = {
    Name = "vpc-a-flow-log"
  }
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.vpc_b.id
  log_destination = "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/ws25/flow/app"
}
resource "aws_iam_role" "vpc_b_iam_role" {
  name = "VpcBFlowLogIamRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["sts:AssumeRole"]
      Principal = {
        Service = ["vpc-flow-logs.amazonaws.com"]
      }
    }]
  })
}
resource "aws_vpc_endpoint" "vpc_bs3_endpoint" {
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.vpc_b_priv_a_rt.id, aws_route_table.vpc_b_priv_b_rt.id, aws_route_table.vpc_b_priv_c_rt.id, aws_route_table.vpc_b_internal_a_rt.id, aws_route_table.vpc_b_internal_c_rt.id]
  vpc_id            = aws_vpc.vpc_b.id
}
resource "aws_vpc_endpoint" "vpc_b_ecr_dkr_endpoint" {
  service_name        = "com.amazonaws.${data.aws_region.current.region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.vpc_b_private_subnet_a.id, aws_subnet.vpc_b_private_subnet_b.id, aws_subnet.vpc_b_private_subnet_c.id]
  security_group_ids  = [aws_security_group.vpc_b_ecr_dkr_endpoint_security_group.id]
  vpc_id              = aws_vpc.vpc_b.id
  private_dns_enabled = true
}
resource "aws_security_group" "vpc_b_ecr_dkr_endpoint_security_group" {
  description = "Security Group"
  name        = "ecr-dkr-vpce-sg"
  ingress {
    protocol    = "tcp"
    from_port   = 443
    to_port     = 443
    cidr_blocks = [var.vpc_b_cidr]
  }
  vpc_id = aws_vpc.vpc_b.id
}
resource "aws_vpc_endpoint" "vpc_b_ecr_api_endpoint" {
  service_name        = "com.amazonaws.${data.aws_region.current.region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.vpc_b_private_subnet_a.id, aws_subnet.vpc_b_private_subnet_b.id, aws_subnet.vpc_b_private_subnet_c.id]
  security_group_ids  = [aws_security_group.vpc_b_ecr_api_endpoint_security_group.id]
  vpc_id              = aws_vpc.vpc_b.id
  private_dns_enabled = true
}
resource "aws_security_group" "vpc_b_ecr_api_endpoint_security_group" {
  description = "Security Group"
  name        = "ecr-api-vpce-sg"
  ingress {
    protocol    = "tcp"
    from_port   = 443
    to_port     = 443
    cidr_blocks = [var.vpc_b_cidr]
  }
  vpc_id = aws_vpc.vpc_b.id
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
    Name = "ws25-ec2-bastion"
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

sed -i 's/#Port 22/Port 10100/' /etc/ssh/sshd_config
sudo systemctl restart sshd
# ssh -i key.pem -p 10100 ec2-user@public_ip

export NLB_PRIVATE_IPS=$(aws ec2 describe-network-interfaces --filters Name=description,Values="ELB ${aws_lb.app_nlb.arn_suffix}" --query 'NetworkInterfaces[*].PrivateIpAddresses[*].PrivateIpAddress' --output text)
TARGETS=""; for IP in $NLB_PRIVATE_IPS; do TARGETS+=" Id=$IP,AvailabilityZone=all"; done
aws elbv2 register-targets --target-group-arn ${aws_lb_target_group.hub_nlb_target_group.arn} --targets $TARGETS

/opt/aws/bin/cfn-signal -e $? --stack ${var.stack_name} --resource BastionEc2 --region ${data.aws_region.current.region}
EOT
  subnet_id                   = aws_subnet.vpc_a_public_subnet_c.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.bastion_ec2_security_group.id]
}
resource "aws_security_group" "bastion_ec2_security_group" {
  description = "Security Group for Bastion EC2 SSH Connection"
  name        = "bastion-sg"
  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 10100
    protocol    = "tcp"
    to_port     = 10100
  }
  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 8000
    protocol    = "tcp"
    to_port     = 8000
  }
  vpc_id = aws_vpc.vpc_a.id
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
  name = "Ec2AdminRole-${local.stack_suffix}"
}
resource "aws_iam_instance_profile" "bastion_ec2_instance_profile" {
  name = "Ec2AdminRole-${local.stack_suffix}"
  # An instance profile holds at most one role, so this attribute is a single
  # role name string - not the list CloudFormation's AWS::IAM::InstanceProfile
  # Roles property takes. jsonencode([...]) here sends the literal string
  # ["terraform-..."] as roleName, which IAM rejects with a ValidationError
  # during apply, while terraform validate and plan both pass because the
  # attribute is a string either way (rules.md A-3).
  role = aws_iam_role.bastion_ec2_iam_role.name
}
resource "aws_eip" "bastion_ec2_elastic_ip" {}
resource "aws_eip_association" "bastion_ec2_elastic_ip_association" {
  allocation_id = aws_eip.bastion_ec2_elastic_ip.allocation_id
  instance_id   = aws_instance.bastion_ec2.id
}
resource "aws_key_pair" "key_pair" {
  key_name   = "key-${local.stack_suffix}"
  public_key = tls_private_key.key_pair.public_key_openssh
}
resource "aws_kms_key" "kms_key" {
  is_enabled              = true
  enable_key_rotation     = true
  rotation_period_in_days = 90
}
resource "aws_kms_alias" "kms_key_alias" {
  name          = "alias/ws25-kms"
  target_key_id = aws_kms_key.kms_key.id
}
resource "aws_secretsmanager_secret" "rds_secret" {
  kms_key_id = aws_kms_key.kms_key.arn
  name       = "ws25/secret/key"
}
resource "aws_rds_cluster" "rds_cluster" {
  cluster_identifier                    = "ws25-rdb-cluster"
  database_name                         = var.rds_database
  engine                                = "aurora-mysql"
  engine_version                        = "8.0.mysql_aurora.3.09.0"
  auto_minor_version_upgrade            = true
  availability_zones                    = ["${data.aws_region.current.region}a", "${data.aws_region.current.region}c"]
  backtrack_window                      = 10800
  backup_retention_period               = 34
  database_insights_mode                = "standard"
  db_subnet_group_name                  = aws_db_subnet_group.rds_subnet_group.id
  enabled_cloudwatch_logs_exports       = ["audit", "error", "general", "instance"]
  kms_key_id                            = aws_kms_key.kms_key.id
  manage_master_user_password           = false
  master_username                       = var.rds_username
  master_password                       = var.rds_password
  monitoring_interval                   = 10
  monitoring_role_arn                   = aws_iam_role.rds_enhanced_monitoring_iam_role.arn
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.kms_key.id
  performance_insights_retention_period = 7
  port                                  = 10101
  storage_encrypted                     = true
  vpc_security_group_ids                = [aws_security_group.rds_security_group.id]
}
resource "aws_db_subnet_group" "rds_subnet_group" {
  description = "RDS SubnetGroup"
  name        = "rds-subnet-group"
  subnet_ids  = [aws_subnet.vpc_b_internal_subnet_a.id, aws_subnet.vpc_b_internal_subnet_c.id]
}
resource "aws_iam_role" "rds_enhanced_monitoring_iam_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["monitoring.rds.amazonaws.com"]
      }
      Action = ["sts:AssumeRole"]
    }]
  })
  name = "RdsEnhancedMonitoringRole"
}
resource "aws_security_group" "rds_security_group" {
  description = "Security Group"
  name        = "rds-sg"
  ingress {
    protocol        = -1
    security_groups = [aws_vpc.vpc_b.default_security_group_id]
    from_port       = 0
    to_port         = 0
  }
  ingress {
    protocol        = "TCP"
    from_port       = 10101
    to_port         = 10101
    security_groups = [aws_security_group.bastion_ec2_security_group.id]
  }
  ingress {
    protocol        = "TCP"
    from_port       = 10101
    to_port         = 10101
    security_groups = [aws_security_group.ecs_service_security_group.id]
  }
  vpc_id = aws_vpc.vpc_b.id
}
resource "aws_db_instance" "rds_instance_a" {
  identifier                  = "rds-instance-a"
  instance_class              = "db.t4g.medium"
  engine                      = "aurora-mysql"
  availability_zone           = "${data.aws_region.current.region}a"
  auto_minor_version_upgrade  = true
  allow_major_version_upgrade = true
  apply_immediately           = true
}
resource "aws_db_instance" "rds_instance_c" {
  identifier                  = "rds-instance-c"
  instance_class              = "db.t4g.medium"
  engine                      = "aurora-mysql"
  availability_zone           = "${data.aws_region.current.region}c"
  auto_minor_version_upgrade  = true
  allow_major_version_upgrade = true
  apply_immediately           = true
}
resource "aws_ecr_repository" "green_ecr" {
  name = "green"
  encryption_configuration {
    encryption_type = "AES256"
  }
  image_scanning_configuration {
    scan_on_push = true
  }
  image_tag_mutability = "IMMUTABLE"
}
resource "aws_ecr_repository" "red_ecr" {
  name = "red"
  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.kms_key.id
  }
  image_scanning_configuration {
    scan_on_push = true
  }
  image_tag_mutability = "IMMUTABLE"
}
resource "aws_ecs_cluster" "ecs_cluster" {
  name = "ws25-ecs-cluster"
  setting {
    name  = "containerInsights"
    value = "enhanced"
  }
  configuration {
    managed_storage_configuration {
      kms_key_id = aws_kms_key.kms_key.id
    }
  }
}
resource "aws_ecs_capacity_provider" "ecs_ec2_capacity_provider" {
  name = "ec2-capacity-provider"
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
  name                = "ecs-asg"
  min_size            = 3
  desired_capacity    = 3
  max_size            = 3
  vpc_zone_identifier = [aws_subnet.vpc_b_private_subnet_a.id, aws_subnet.vpc_b_private_subnet_b.id, aws_subnet.vpc_b_private_subnet_c.id]
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
  name          = "asg-launch-template"
  image_id      = data.aws_ssm_parameter.ecs_ami_id.insecure_value
  instance_type = "t3.medium"
  iam_instance_profile {
    name = aws_iam_instance_profile.ecs_container_instance_profile.name
  }
  vpc_security_group_ids = [aws_security_group.ecs_container_instance_security_group.id]
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
      Name = "ws25-ecs-container-green"
    }
  }
}
resource "aws_security_group" "ecs_container_instance_security_group" {
  description = "Security Group"
  name        = "ecs-container-instance-sg"
  ingress {
    protocol        = -1
    security_groups = [aws_vpc.vpc_b.default_security_group_id]
    from_port       = 0
    to_port         = 0
  }
  vpc_id = aws_vpc.vpc_b.id
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
  name = "ContainerInstanceIamRole"
}
resource "aws_iam_instance_profile" "ecs_container_instance_profile" {
  name = "ContainerInstanceProfile-${local.stack_suffix}"
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
resource "aws_security_group" "ecs_service_security_group" {
  description = "Security Group"
  name        = "ecs-service-sg"
  ingress {
    protocol        = -1
    security_groups = [aws_vpc.vpc_b.default_security_group_id]
    from_port       = 0
    to_port         = 0
  }
  ingress {
    protocol        = "TCP"
    from_port       = 8080
    to_port         = 8080
    security_groups = [aws_security_group.bastion_ec2_security_group.id]
  }
  ingress {
    protocol        = "TCP"
    from_port       = 8080
    to_port         = 8080
    security_groups = [aws_security_group.app_alb_security_group.id]
  }
  vpc_id = aws_vpc.vpc_b.id
}
resource "aws_ecs_task_definition" "green_task_definition" {
  family = "ws25-ecs-green-taskdef"
  cpu    = "1024"
  memory = "1024"
  container_definitions = jsonencode([{
    Name      = "green"
    Image     = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.region}.amazonaws.com/green:v1.0.0"
    Essential = true
    HealthCheck = {
      Command     = ["CMD-SHELL", "curl -f http://localhost:8080/health || exit 1"]
      Interval    = 30
      Retries     = 5
      StartPeriod = 5
      Timeout     = 5
    }
    PortMappings = [{
      ContainerPort = 8080
      HostPort      = 8080
      Name          = "http"
    }]
    Secrets = [{
      Name      = "DB_URL"
      ValueFrom = "${aws_secretsmanager_secret.rds_secret.arn}:DB_URL::"
      }, {
      Name      = "DB_USER"
      ValueFrom = "${aws_secretsmanager_secret.rds_secret.arn}:DB_USER::"
      }, {
      Name      = "DB_PASSWD"
      ValueFrom = "${aws_secretsmanager_secret.rds_secret.arn}:DB_PASSWD::"
    }]
    LogConfiguration = {
      LogDriver = "awsfirelens"
      Options = {
        Name              = "cloudwatch"
        log_group_name    = "/ws25/logs/green"
        auto_create_group = "true"
        log_stream_name   = "Green-$(ecs_task_id)"
        region            = data.aws_region.current.region
        "exclude-pattern" = "health"
      }
    }
    }, {
    Name      = "log_router"
    Image     = "public.ecr.aws/aws-observability/aws-for-fluent-bit:stable"
    Essential = true
    User      = "0"
    FirelensConfiguration = {
      Type = "fluentbit"
    }
    LogConfiguration = {
      LogDriver = "awslogs"
      Options = {
        "awslogs-group"         = "firelens"
        "awslogs-region"        = data.aws_region.current.region
        "awslogs-create-group"  = "true"
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
  network_mode             = "awsvpc"
  requires_compatibilities = ["EC2"]
  runtime_platform {
    cpu_architecture        = "X86_64"
    operating_system_family = "LINUX"
  }
  task_role_arn      = aws_iam_role.ecs_task_role.arn
  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn
  depends_on         = [aws_ssm_association.ecr_ssm_association]
}
resource "aws_ecs_task_definition" "red_task_definition" {
  family = "ws25-ecs-red-taskdef"
  cpu    = "512"
  memory = "1024"
  container_definitions = jsonencode([{
    Name      = "red"
    Image     = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.region}.amazonaws.com/red:v1.0.0"
    Essential = true
    HealthCheck = {
      Command     = ["CMD-SHELL", "curl -f http://localhost:8080/health || exit 1"]
      Interval    = 30
      Retries     = 5
      StartPeriod = 5
      Timeout     = 5
    }
    PortMappings = [{
      ContainerPort = 8080
      HostPort      = 8080
      Name          = "http"
    }]
    Secrets = [{
      Name      = "DB_URL"
      ValueFrom = "${aws_secretsmanager_secret.rds_secret.arn}:DB_URL::"
      }, {
      Name      = "DB_USER"
      ValueFrom = "${aws_secretsmanager_secret.rds_secret.arn}:DB_USER::"
      }, {
      Name      = "DB_PASSWD"
      ValueFrom = "${aws_secretsmanager_secret.rds_secret.arn}:DB_PASSWD::"
    }]
    LogConfiguration = {
      LogDriver = "awsfirelens"
      Options = {
        Name              = "cloudwatch"
        log_group_name    = "/ws25/logs/red"
        auto_create_group = "true"
        log_stream_name   = "Red-$(ecs_task_id)"
        region            = data.aws_region.current.region
        "exclude-pattern" = "health"
      }
    }
    }, {
    Name      = "log_router"
    Image     = "public.ecr.aws/aws-observability/aws-for-fluent-bit:stable"
    Essential = true
    User      = "0"
    FirelensConfiguration = {
      Type = "fluentbit"
    }
    LogConfiguration = {
      LogDriver = "awslogs"
      Options = {
        "awslogs-group"         = "firelens"
        "awslogs-region"        = data.aws_region.current.region
        "awslogs-create-group"  = "true"
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  runtime_platform {
    cpu_architecture        = "X86_64"
    operating_system_family = "LINUX"
  }
  task_role_arn      = aws_iam_role.ecs_task_role.arn
  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn
  depends_on         = [aws_ssm_association.ecr_ssm_association]
}
resource "aws_ecs_service" "green_service" {
  name                          = "ws25-ecs-green"
  cluster                       = aws_ecs_cluster.ecs_cluster.name
  task_definition               = aws_ecs_task_definition.green_task_definition.arn
  desired_count                 = 3
  availability_zone_rebalancing = "ENABLED"
  launch_type                   = "EC2"
  deployment_controller {
    type = "CODE_DEPLOY"
  }
  network_configuration {
    assign_public_ip = false
    security_groups  = [aws_security_group.ecs_service_security_group.id]
    subnets          = [aws_subnet.vpc_b_private_subnet_a.id, aws_subnet.vpc_b_private_subnet_b.id, aws_subnet.vpc_b_private_subnet_c.id]
  }
  load_balancer {
    container_name   = "green"
    container_port   = 8080
    target_group_arn = aws_lb_target_group.green_target_group_blue.arn
  }
  depends_on = [aws_lb_listener_rule.green_listener_rule, aws_lb_listener_rule.red_listener_rule]
}
resource "aws_ecs_service" "red_service" {
  name                          = "ws25-ecs-red"
  cluster                       = aws_ecs_cluster.ecs_cluster.name
  task_definition               = aws_ecs_task_definition.red_task_definition.arn
  desired_count                 = 3
  availability_zone_rebalancing = "ENABLED"
  launch_type                   = "FARGATE"
  platform_version              = "LATEST"
  deployment_controller {
    type = "CODE_DEPLOY"
  }
  network_configuration {
    assign_public_ip = false
    security_groups  = [aws_security_group.ecs_service_security_group.id]
    subnets          = [aws_subnet.vpc_b_private_subnet_a.id, aws_subnet.vpc_b_private_subnet_b.id, aws_subnet.vpc_b_private_subnet_c.id]
  }
  load_balancer {
    container_name   = "red"
    container_port   = 8080
    target_group_arn = aws_lb_target_group.red_target_group_blue.arn
  }
  depends_on = [aws_lb_listener_rule.green_listener_rule, aws_lb_listener_rule.red_listener_rule]
}
resource "aws_lb" "app_alb" {
  name               = "ws25-app-alb"
  subnets            = [aws_subnet.vpc_b_private_subnet_a.id, aws_subnet.vpc_b_private_subnet_b.id, aws_subnet.vpc_b_private_subnet_c.id]
  security_groups    = [aws_security_group.app_alb_security_group.id]
  load_balancer_type = "application"
  internal           = true
}
resource "aws_security_group" "app_alb_security_group" {
  description = "Security Group"
  name        = "app-alb-sg"
  ingress {
    protocol        = -1
    security_groups = [aws_vpc.vpc_b.default_security_group_id]
    from_port       = 0
    to_port         = 0
  }
  ingress {
    protocol        = "TCP"
    from_port       = 80
    to_port         = 80
    security_groups = [aws_security_group.app_nlb_security_group.id]
  }
  vpc_id = aws_vpc.vpc_b.id
}
resource "aws_lb_listener" "app_alb_listener" {
  load_balancer_arn = aws_lb.app_alb.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type = "fixed-response"
    fixed_response {
      status_code  = 404
      content_type = "text/plain"
      message_body = "<center><h1>404 Not Found</h1></center>"
    }
  }
}
resource "aws_lb_listener_rule" "green_listener_rule" {
  listener_arn = aws_lb_listener.app_alb_listener.arn
  priority     = 1
  condition {
    path_pattern {
      values = ["/green/", "/green"]
    }
  }
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.green_target_group_blue.arn
  }
}
resource "aws_lb_listener_rule" "red_listener_rule" {
  listener_arn = aws_lb_listener.app_alb_listener.arn
  priority     = 2
  condition {
    path_pattern {
      values = ["/red/", "/red"]
    }
  }
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.red_target_group_blue.arn
  }
}
resource "aws_lb_listener_rule" "green_health_check_listener_rule" {
  listener_arn = aws_lb_listener.app_alb_listener.arn
  priority     = 3
  condition {
    path_pattern {
      values = ["/health"]
    }
  }
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.green_target_group_blue.arn
  }
}
resource "aws_lb_listener_rule" "red_health_check_listener_rule" {
  listener_arn = aws_lb_listener.app_alb_listener.arn
  priority     = 4
  condition {
    path_pattern {
      values = ["/health"]
    }
  }
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.red_target_group_blue.arn
  }
}
resource "aws_lb_listener_rule" "error_listener_rule" {
  listener_arn = aws_lb_listener.app_alb_listener.arn
  priority     = 5
  condition {
    path_pattern {
      values = ["/error"]
    }
  }
  action {
    type = "fixed-response"
    fixed_response {
      status_code  = 500
      content_type = "text/plain"
      message_body = "<center><h1>500 Internal Server Error</h1></center>"
    }
  }
}
resource "aws_lb_target_group" "green_target_group_blue" {
  name        = "ws25-ecs-green-tg-blue"
  port        = 8080
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.vpc_b.id
  health_check {
    path     = "/health"
    protocol = "HTTP"
    port     = 8080
  }
  deregistration_delay = "30"
}
resource "aws_lb_target_group" "green_target_group_green" {
  name        = "ws25-ecs-green-tg-green"
  port        = 8080
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.vpc_b.id
  health_check {
    path     = "/health"
    protocol = "HTTP"
    port     = 8080
  }
  deregistration_delay = "30"
}
resource "aws_lb_target_group" "red_target_group_blue" {
  name        = "ws25-ecs-red-tg-blue"
  port        = 8080
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.vpc_b.id
  health_check {
    path     = "/health"
    protocol = "HTTP"
    port     = 8080
  }
  deregistration_delay = "30"
}
resource "aws_lb_target_group" "red_target_group_green" {
  name        = "ws25-ecs-red-tg-green"
  port        = 8080
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.vpc_b.id
  health_check {
    path     = "/health"
    protocol = "HTTP"
    port     = 8080
  }
  deregistration_delay = "30"
}
resource "aws_ssm_association" "ecr_ssm_association" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = 900
  targets {
    key    = "InstanceIds"
    values = [aws_instance.bastion_ec2.id]
  }
  parameters = {
    commands = join("\n", ["dnf install -yq docker\nsystemctl start docker\nsystemctl enable docker\n# usermod -aG docker ec2-user\n# newgrp docker\nchmod 666 /var/run/docker.sock\n\nsu - ec2-user << EOF\ncd /home/ec2-user\ngit clone https://github.com/iamhansko/aws-cloudformation-templates.git\nmv aws-cloudformation-templates/024_cross_vpc_ecs_bluegreen/src/* /home/ec2-user/\n\naws ecr get-login-password --region ${data.aws_region.current.region} | docker login --username AWS --password-stdin ${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.region}.amazonaws.com\n\necho 'FROM ubuntu:latest\nENV CGO_ENABLED 0\nWORKDIR /app\nCOPY ./green_1.0.0 ./green_1.0.0\nRUN apt-get update && apt-get install -y curl\nRUN chmod +x ./green_1.0.0\nRUN useradd -u 2000 green\nUSER green\nEXPOSE 8080\nCMD [\"./green_1.0.0\"]' > Dockerfile.green100\ndocker build -f Dockerfile.green100 -t ${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.region}.amazonaws.com/green:v1.0.0 .\ndocker push ${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.region}.amazonaws.com/green:v1.0.0\n\necho 'FROM ubuntu:latest\nENV CGO_ENABLED 0\nWORKDIR /app\nCOPY ./green_1.0.1 ./green_1.0.1\nRUN apt-get update && apt-get install -y curl\nRUN chmod +x ./green_1.0.1\nRUN useradd -u 2000 green\nUSER green\nEXPOSE 8080\nCMD [\"./green_1.0.1\"]' > Dockerfile.green101\ndocker build -f Dockerfile.green101 -t ${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.region}.amazonaws.com/green:v1.0.1 .\ndocker push ${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.region}.amazonaws.com/green:v1.0.1\n\necho 'FROM ubuntu:latest\nENV CGO_ENABLED 0\nWORKDIR /app\nCOPY ./red_1.0.0 ./red_1.0.0\nRUN apt-get update && apt-get install -y curl\nRUN chmod +x ./red_1.0.0\nRUN useradd -u 2000 red\nUSER red\nEXPOSE 8080\nCMD [\"./red_1.0.0\"]' > Dockerfile.red100\ndocker build -f Dockerfile.red100 -t ${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.region}.amazonaws.com/red:v1.0.0 .\ndocker push ${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.region}.amazonaws.com/red:v1.0.0\n\necho 'FROM ubuntu:latest\nENV CGO_ENABLED 0\nWORKDIR /app\nCOPY ./red_1.0.1 ./red_1.0.1\nRUN apt-get update && apt-get install -y curl\nRUN chmod +x ./red_1.0.1\nRUN useradd -u 2000 red\nUSER red\nEXPOSE 8080\nCMD [\"./red_1.0.1\"]' > Dockerfile.red101\ndocker build -f Dockerfile.red101 -t ${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.region}.amazonaws.com/red:v1.0.1 .\ndocker push ${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.region}.amazonaws.com/red:v1.0.1\n\nEOF\n"])
  }
  depends_on = [aws_ecr_repository.green_ecr, aws_ecr_repository.red_ecr]
}
resource "aws_ssm_association" "code_suite_ssm_association" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = 900
  targets {
    key    = "InstanceIds"
    values = [aws_instance.bastion_ec2.id]
  }
  parameters = {
    commands = join("\n", ["su - ec2-user << EOF\nmkdir -p /home/ec2-user/pipeline/artifact/green\nmkdir -p /home/ec2-user/pipeline/artifact/red\n\nsleep 10\n\ncd /home/ec2-user/pipeline/artifact/green\necho '{\"ImageURI\": \"${aws_ecr_repository.green_ecr.repository_url}:v1.0.1\"}' > imageDetail.json\naws ecs describe-task-definition --task-definition \"ws25-ecs-green-taskdef\" --query 'taskDefinition' --output json > temp.json\njq '.containerDefinitions |= map( if .name == \"green\" then .image = \"<IMAGE1_NAME>\" else . end ) | del(.revision, .status, .taskDefinitionArn, .requiresAttributes, .compatibilities, .\"registeredAt\", .\"registeredBy\")' temp.json > taskdef.json\nrm temp.json\necho \"version: 0.0\nResources:\n  - TargetService:\n      Type: AWS::ECS::Service\n      Properties:\n        TaskDefinition: <TASK_DEFINITION>\n        LoadBalancerInfo:\n          ContainerName: green\n          ContainerPort: 8080\" > appspec.yaml\necho '#!/bin/bash\ncd /home/ec2-user/pipeline/artifact/green\nzip artifact.zip *\naws s3 cp artifact.zip s3://${aws_s3_bucket.green_source_s3_bucket.id}\nrm artifact.zip' > /home/ec2-user/pipeline/green.sh\nchmod +x /home/ec2-user/pipeline/green.sh\n\ncd /home/ec2-user/pipeline/artifact/red\necho '{\"ImageURI\": \"${aws_ecr_repository.red_ecr.repository_url}:v1.0.1\"}' > imageDetail.json\naws ecs describe-task-definition --task-definition \"ws25-ecs-red-taskdef\" --query 'taskDefinition' --output json > temp.json\njq '.containerDefinitions |= map( if .name == \"red\" then .image = \"<IMAGE1_NAME>\" else . end ) | del(.revision, .status, .taskDefinitionArn, .requiresAttributes, .compatibilities, .\"registeredAt\", .\"registeredBy\")' temp.json > taskdef.json\nrm temp.json\necho \"version: 0.0\nResources:\n  - TargetService:\n      Type: AWS::ECS::Service\n      Properties:\n        TaskDefinition: <TASK_DEFINITION>\n        LoadBalancerInfo:\n          ContainerName: red\n          ContainerPort: 8080\" > appspec.yaml\necho '#!/bin/bash\ncd /home/ec2-user/pipeline/artifact/red\nzip artifact.zip *\naws s3 cp artifact.zip s3://${aws_s3_bucket.red_source_s3_bucket.id}\nrm artifact.zip' > /home/ec2-user/pipeline/red.sh\nchmod +x /home/ec2-user/pipeline/red.sh\n\nEOF\n"])
  }
  depends_on = [aws_ecs_task_definition.green_task_definition, aws_ecs_task_definition.red_task_definition]
}
resource "aws_ssm_association" "sql_ssm_association" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = 900
  targets {
    key    = "InstanceIds"
    values = [aws_instance.bastion_ec2.id]
  }
  parameters = {
    commands = join("\n", ["su - ec2-user << EOF\ncd /home/ec2-user\n\necho 'CREATE DATABASE IF NOT EXISTS day1;\n\nUSE day1;\n\nCREATE TABLE IF NOT EXISTS green (\n    uuid VARCHAR(8) PRIMARY KEY,\n    x VARCHAR(255) NOT NULL,\n    y DOUBLE NOT NULL\n);\n\nCREATE TABLE IF NOT EXISTS red (\n    uuid VARCHAR(8) PRIMARY KEY,\n    name VARCHAR(255) NOT NULL\n);' > /home/ec2-user/day1_table_v1.sql\n\nsudo dnf install mariadb105 -yq\n\nsleep 300\n\nmysql -u ${var.rds_username} -p'${var.rds_password}' -h ${aws_rds_cluster.rds_cluster.endpoint} -P 10101 ${var.rds_database} < /home/ec2-user/day1_table_v1.sql\nmysql -u ${var.rds_username} -p'${var.rds_password}' -h ${aws_rds_cluster.rds_cluster.endpoint} -P 10101 ${var.rds_database} -e \"SHOW TABLES;\"\n\nEOF\n"])
  }
  depends_on = [aws_rds_cluster.rds_cluster, aws_db_instance.rds_instance_a, aws_db_instance.rds_instance_c]
}
resource "aws_lb" "hub_nlb" {
  name               = "ws25-hub-nlb"
  subnets            = [aws_subnet.vpc_a_public_subnet_a.id, aws_subnet.vpc_a_public_subnet_c.id]
  security_groups    = [aws_security_group.hub_nlb_security_group.id]
  load_balancer_type = "network"
  internal           = false
}
resource "aws_security_group" "hub_nlb_security_group" {
  description = "Security Group"
  name        = "hub-nlb-sg"
  ingress {
    protocol        = -1
    security_groups = [aws_vpc.vpc_a.default_security_group_id]
    from_port       = 0
    to_port         = 0
  }
  ingress {
    protocol    = "TCP"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }
  vpc_id = aws_vpc.vpc_a.id
}
resource "aws_lb_listener" "hub_nlb_listener" {
  load_balancer_arn = aws_lb.hub_nlb.arn
  port              = 80
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.hub_nlb_target_group.arn
  }
}
resource "aws_lb_target_group" "hub_nlb_target_group" {
  name                 = "ws25-hub-nlb-tg"
  port                 = 80
  protocol             = "TCP"
  target_type          = "ip"
  vpc_id               = aws_vpc.vpc_a.id
  deregistration_delay = "30"
}
resource "aws_lb" "app_nlb" {
  name               = "ws25-app-nlb"
  subnets            = [aws_subnet.vpc_b_private_subnet_a.id, aws_subnet.vpc_b_private_subnet_b.id, aws_subnet.vpc_b_private_subnet_c.id]
  security_groups    = [aws_security_group.app_nlb_security_group.id]
  load_balancer_type = "network"
  internal           = true
}
resource "aws_security_group" "app_nlb_security_group" {
  description = "Security Group"
  name        = "app-nlb-sg"
  ingress {
    protocol        = -1
    security_groups = [aws_vpc.vpc_b.default_security_group_id]
    from_port       = 0
    to_port         = 0
  }
  ingress {
    protocol        = "TCP"
    from_port       = 80
    to_port         = 80
    security_groups = [aws_security_group.hub_nlb_security_group.id]
  }
  vpc_id = aws_vpc.vpc_b.id
}
resource "aws_lb_listener" "app_nlb_listener" {
  load_balancer_arn = aws_lb.app_nlb.arn
  port              = 80
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_nlb_target_group.arn
  }
}
resource "aws_lb_target_group" "app_nlb_target_group" {
  name        = "ws25-app-nlb-tg"
  port        = 80
  protocol    = "TCP"
  target_type = "alb"
  vpc_id      = aws_vpc.vpc_b.id
  health_check {
    path = "/health"
  }
}
resource "aws_s3_bucket" "green_source_s3_bucket" {
  bucket = "ws25-cd-green-artifact-${var.random_number}"
}
resource "aws_s3_bucket" "red_source_s3_bucket" {
  bucket = "ws25-cd-red-artifact-${var.random_number}"
}
resource "aws_codedeploy_app" "green_code_deploy_application" {
  name             = "ws25-cd-green-app"
  compute_platform = "ECS"
}
resource "aws_codedeploy_deployment_group" "green_code_deploy_deployment_group" {
  app_name = aws_codedeploy_app.green_code_deploy_application.name
  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM", "DEPLOYMENT_STOP_ON_REQUEST"]
  }
  deployment_group_name  = "ws25-cd-green-dg"
  service_role_arn       = aws_iam_role.code_deploy_iam_role.arn
  deployment_config_name = "CodeDeployDefault.ECSAllAtOnce"
  deployment_style {
    deployment_option = "WITH_TRAFFIC_CONTROL"
    deployment_type   = "BLUE_GREEN"
  }
  ecs_service {
    cluster_name = aws_ecs_cluster.ecs_cluster.name
    service_name = aws_ecs_service.green_service.name
  }
  load_balancer_info {
    target_group_pair_info {
      prod_traffic_route {
        listener_arns = [aws_lb_listener.app_alb_listener.arn]
      }
      target_group {
        name = aws_lb_target_group.green_target_group_blue.name
      }
      target_group {
        name = aws_lb_target_group.green_target_group_green.name
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
  name = "CodeDeployRole-${local.stack_suffix}"
}
resource "aws_codepipeline" "green_code_pipeline" {
  name          = "ws25-cd-green-pipeline"
  pipeline_type = "V2"
  artifact_store {
    location = aws_s3_bucket.green_code_pipeline_artifact_store_s3_bucket.id
    type     = "S3"
  }
  role_arn       = aws_iam_role.code_pipeline_iam_role.arn
  execution_mode = "QUEUED"
  stage {
    name = "Source"
    action {
      name = "SourceAction"
      configuration = {
        S3Bucket             = aws_s3_bucket.green_source_s3_bucket.id
        S3ObjectKey          = "artifact.zip"
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
    name = "Deploy"
    action {
      name = "DeployAction"
      configuration = {
        ApplicationName                = aws_codedeploy_app.green_code_deploy_application.name
        DeploymentGroupName            = aws_codedeploy_deployment_group.green_code_deploy_deployment_group.id
        Image1ArtifactName             = "SourceOutput"
        Image1ContainerName            = "IMAGE1_NAME"
        TaskDefinitionTemplateArtifact = "SourceOutput"
        TaskDefinitionTemplatePath     = "taskdef.json"
        AppSpecTemplateArtifact        = "SourceOutput"
        AppSpecTemplatePath            = "appspec.yaml"
      }
      input_artifacts = ["SourceOutput"]
      category        = "Deploy"
      owner           = "AWS"
      provider        = "CodeDeployToECS"
      version         = 1
    }
  }
}
resource "aws_s3_bucket" "green_code_pipeline_artifact_store_s3_bucket" {}
resource "aws_codedeploy_app" "red_code_deploy_application" {
  name             = "ws25-cd-red-app"
  compute_platform = "ECS"
}
resource "aws_codedeploy_deployment_group" "red_code_deploy_deployment_group" {
  app_name = aws_codedeploy_app.red_code_deploy_application.name
  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM", "DEPLOYMENT_STOP_ON_REQUEST"]
  }
  deployment_group_name  = "ws25-cd-red-dg"
  service_role_arn       = aws_iam_role.code_deploy_iam_role.arn
  deployment_config_name = "CodeDeployDefault.ECSAllAtOnce"
  deployment_style {
    deployment_option = "WITH_TRAFFIC_CONTROL"
    deployment_type   = "BLUE_GREEN"
  }
  ecs_service {
    cluster_name = aws_ecs_cluster.ecs_cluster.name
    service_name = aws_ecs_service.red_service.name
  }
  load_balancer_info {
    target_group_pair_info {
      prod_traffic_route {
        listener_arns = [aws_lb_listener.app_alb_listener.arn]
      }
      target_group {
        name = aws_lb_target_group.red_target_group_blue.name
      }
      target_group {
        name = aws_lb_target_group.red_target_group_green.name
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
}
resource "aws_codepipeline" "red_code_pipeline" {
  name          = "ws25-cd-red-pipeline"
  pipeline_type = "V2"
  artifact_store {
    location = aws_s3_bucket.red_code_pipeline_artifact_store_s3_bucket.id
    type     = "S3"
  }
  role_arn       = aws_iam_role.code_pipeline_iam_role.arn
  execution_mode = "QUEUED"
  stage {
    name = "Source"
    action {
      name = "SourceAction"
      configuration = {
        S3Bucket             = aws_s3_bucket.red_source_s3_bucket.id
        S3ObjectKey          = "artifact.zip"
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
    name = "Deploy"
    action {
      name = "DeployAction"
      configuration = {
        ApplicationName                = aws_codedeploy_app.red_code_deploy_application.name
        DeploymentGroupName            = aws_codedeploy_deployment_group.red_code_deploy_deployment_group.id
        Image1ArtifactName             = "SourceOutput"
        Image1ContainerName            = "IMAGE1_NAME"
        TaskDefinitionTemplateArtifact = "SourceOutput"
        TaskDefinitionTemplatePath     = "taskdef.json"
        AppSpecTemplateArtifact        = "SourceOutput"
        AppSpecTemplatePath            = "appspec.yaml"
      }
      input_artifacts = ["SourceOutput"]
      category        = "Deploy"
      owner           = "AWS"
      provider        = "CodeDeployToECS"
      version         = 1
    }
  }
}
resource "aws_s3_bucket" "red_code_pipeline_artifact_store_s3_bucket" {}
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
  name = "CodePipelineRole-${local.stack_suffix}"
}
resource "aws_cloudwatch_event_rule" "green_cloud_watch_event_rule" {
  description    = "CodePipeline Source Stage에서 변경이 발생하면 파이프라인을 자동으로 시작하는 Amazon CloudWatch Events 규칙입니다. 이 규칙을 삭제하면 해당 파이프라인에서 변경 사항이 감지되지 않습니다. 자세한 정보 : http://docs.aws.amazon.com/codepipeline/latest/userguide/pipelines-about-starting.html"
  event_bus_name = "default"
  event_pattern = jsonencode({
    source        = ["aws.s3"]
    "detail-type" = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource = ["s3.amazonaws.com"]
      eventName   = ["CopyObject", "PutObject", "CompleteMultipartUpload"]
      requestParameters = {
        bucketName = [aws_s3_bucket.green_source_s3_bucket.id]
        key        = ["artifact.zip"]
      }
    }
  })
  name  = "green-codepipeline-event-rule"
  state = "ENABLED"
}
resource "aws_cloudwatch_event_rule" "red_cloud_watch_event_rule" {
  description    = "CodePipeline Source Stage에서 변경이 발생하면 파이프라인을 자동으로 시작하는 Amazon CloudWatch Events 규칙입니다. 이 규칙을 삭제하면 해당 파이프라인에서 변경 사항이 감지되지 않습니다. 자세한 정보 : http://docs.aws.amazon.com/codepipeline/latest/userguide/pipelines-about-starting.html"
  event_bus_name = "default"
  event_pattern = jsonencode({
    source        = ["aws.s3"]
    "detail-type" = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource = ["s3.amazonaws.com"]
      eventName   = ["CopyObject", "PutObject", "CompleteMultipartUpload"]
      requestParameters = {
        bucketName = [aws_s3_bucket.red_source_s3_bucket.id]
        key        = ["artifact.zip"]
      }
    }
  })
  name  = "red-codepipeline-event-rule"
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
  name = "CloudWatchEventRuleRole-${local.stack_suffix}"
}
resource "aws_cloudtrail" "cloud_trail" {
  name = "codepipeline-source-trail"
  event_selector {
    data_resource {
      type   = "AWS::S3::Object"
      values = ["${aws_s3_bucket.green_source_s3_bucket.arn}/artifact.zip", "${aws_s3_bucket.red_source_s3_bucket.arn}/artifact.zip"]
    }
    read_write_type = "WriteOnly"
  }
  enable_logging = true
  s3_bucket_name = aws_s3_bucket.cloud_trail_logs_bucket.id
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
          "aws:SourceArn" = "arn:aws:cloudtrail:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:trail/codepipeline-source-trail"
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
          "aws:SourceArn" = "arn:aws:cloudtrail:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:trail/codepipeline-source-trail"
        }
      }
    }]
  })
}
resource "aws_cloudwatch_dashboard" "cloud_watch_dashboard" {
  dashboard_name = "ws25-metrics"
  dashboard_body = <<EOT
{
    "widgets": [
        {
            "type": "metric",
            "x": 12,
            "y": 6,
            "width": 6,
            "height": 6,
            "properties": {
                "metrics": [
                    [ "AWS/ApplicationELB", "HTTPCode_ELB_4XX_Count", "LoadBalancer", "${aws_lb.app_alb.arn_suffix}", { "region": "${data.aws_region.current.region}" } ],
                    [ "AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", "LoadBalancer", "${aws_lb.app_alb.arn_suffix}", { "region": "${data.aws_region.current.region}" } ]
                ],
                "title": "HTTPCode_ELB_4XX_Count, HTTPCode_ELB_5XX_Count",
                "region": "${data.aws_region.current.region}",
                "period": 60,
                "stat": "Sum"
            }
        },
        {
            "type": "metric",
            "x": 18,
            "y": 0,
            "width": 6,
            "height": 6,
            "properties": {
                "region": "${data.aws_region.current.region}",
                "title": "Top 서비스 per CPU 사용률",
                "legend": {
                    "position": "right"
                },
                "timezone": "LOCAL",
                "metrics": [
                    [ { "expression": "SELECT AVG(CPUUtilization) FROM SCHEMA(\"AWS/ECS\", ClusterName, ServiceName)  GROUP BY ClusterName, ServiceName ORDER BY AVG() DESC LIMIT 10" } ]
                ],
                "liveData": false,
                "period": 60,
                "annotations": {
                    "horizontal": [
                        {
                            "value": 80,
                            "label": "High Utilization >="
                        }
                    ]
                },
                "yAxis": {
                    "left": {
                        "min": 0,
                        "showUnits": false
                    }
                }
            }
        },
        {
            "type": "metric",
            "x": 0,
            "y": 6,
            "width": 6,
            "height": 6,
            "properties": {
                "region": "${data.aws_region.current.region}",
                "title": "Top 작업 per CPU 사용률",
                "legend": {
                    "position": "right"
                },
                "timezone": "LOCAL",
                "metrics": [
                    [ { "expression": "SELECT MAX(TaskCpuUtilization) FROM SCHEMA(\"ECS/ContainerInsights\", ClusterName, TaskDefinitionFamily, TaskId)  GROUP BY ClusterName, TaskDefinitionFamily, TaskId ORDER BY MAX() DESC LIMIT 10" } ]
                ],
                "liveData": false,
                "period": 60,
                "yAxis": {
                    "left": {
                        "min": 0,
                        "showUnits": false
                    }
                }
            }
        },
        {
            "type": "metric",
            "x": 6,
            "y": 6,
            "width": 6,
            "height": 6,
            "properties": {
                "region": "${data.aws_region.current.region}",
                "title": "Top 컨테이너 per CPU 사용률",
                "legend": {
                    "position": "right"
                },
                "timezone": "LOCAL",
                "metrics": [
                    [ { "expression": "SELECT MAX(ContainerCpuUtilization) FROM SCHEMA(\"ECS/ContainerInsights\", ClusterName, TaskDefinitionFamily, TaskId, ContainerName)  GROUP BY ClusterName, TaskDefinitionFamily, TaskId, ContainerName ORDER BY MAX() DESC LIMIT 10" } ]
                ],
                "liveData": false,
                "period": 60,
                "yAxis": {
                    "left": {
                        "min": 0,
                        "showUnits": false
                    }
                }
            }
        },
        {
            "type": "log",
            "x": 12,
            "y": 0,
            "width": 6,
            "height": 6,
            "properties": {
                "query": "SOURCE '/ws25/logs/red' | fields @message, @timestamp\n| stats \nsum(if(@message like /GET \\/red/, 1, 0)) as get_red,\nsum(if(@message like /POST \\/red/, 1, 0)) as post_red\nby bin(1m)",
                "region": "${data.aws_region.current.region}",
                "stacked": false,
                "title": "GET /red, POST /red",
                "view": "timeSeries"
            }
        },
        {
            "type": "log",
            "x": 6,
            "y": 0,
            "width": 6,
            "height": 6,
            "properties": {
                "query": "SOURCE '/ws25/logs/green' | fields @message, @timestamp\n| stats \nsum(if(@message like /GET \\/green/, 1, 0)) as get_green,\nsum(if(@message like /POST \\/green/, 1, 0)) as post_green\nby bin(1m)",
                "region": "${data.aws_region.current.region}",
                "stacked": false,
                "title": "GET /green, POST /green",
                "view": "timeSeries"
            }
        },
        {
            "type": "log",
            "x": 0,
            "y": 0,
            "width": 6,
            "height": 6,
            "properties": {
                "query": "SOURCE '/ws25/flow/app' | SOURCE '/ws25/flow/hub' | fields @message, @timestamp, @LogGroup\n| filter @message like /ACCEPT/\n| stats \nsum(if(@log = \"463470958750:/ws25/flow/hub\" , 1, 0)) as ws25_hub_vpc_accpet,\nsum(if(@log = \"463470958750:/ws25/flow/app\", 1, 0)) as ws25_app_vpc_accept\nby bin(1m)",
                "region": "${data.aws_region.current.region}",
                "stacked": false,
                "title": "ws25-hub-vpc, ws25-app-vpc",
                "view": "timeSeries"
            }
        }
    ]
}
EOT
}
resource "aws_cloudwatch_metric_alarm" "app_alb4xx_alarm" {
  alarm_name          = "ws25-app-alb-4xx-alarm"
  alarm_description   = "5분 내 4xx 10건 이상 발생 시 알람"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_ELB_4XX_Count"
  dimensions          = {}
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 10
  comparison_operator = "GreaterThanOrEqualToThreshold"
}
resource "aws_cloudwatch_metric_alarm" "app_alb5xx_alarm" {
  alarm_name          = "ws25-app-alb-5xx-alarm"
  alarm_description   = "5분 내 5xx 5건 이상 발생 시 알람"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_ELB_5XX_Count"
  dimensions          = {}
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 5
  comparison_operator = "GreaterThanOrEqualToThreshold"
}
