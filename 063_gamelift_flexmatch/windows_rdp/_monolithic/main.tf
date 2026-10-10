# Generated from 063_gamelift_flexmatch/windows_rdp.yaml by tools/cfn2tf.
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
  default     = "windows-rdp"
  description = "Stands in for AWS::StackName."
}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}
# Provides the unique suffix that AWS::StackId supplies in CloudFormation.
resource "random_uuid" "stack_id" {}
# --- Parameters ---
variable "username" {
  type    = string
  default = "gamelift"
}
variable "windows_server_ami_id" {
  type        = string
  default     = "/aws/service/ami-windows-latest/Windows_Server-2025-Korean-Full-Base"
  description = "(SSM parameter path; resolved by the aws_ssm_parameter data source)"
}
data "aws_ssm_parameter" "windows_server_ami_id" {
  name = var.windows_server_ami_id
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
resource "aws_s3_bucket_website_configuration" "web_s3_bucket_website" {
  bucket = aws_s3_bucket.web_s3_bucket.id
  index_document {
    suffix = "index.html"
  }
}
resource "aws_s3_bucket_public_access_block" "web_s3_bucket_pab" {
  bucket                  = aws_s3_bucket.web_s3_bucket.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}
resource "aws_iam_role_policy" "game_lift_policy_role_0" {
  name = "GameLiftPolicy"
  role = aws_iam_role.gomoku_game_sqs_process.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["gamelift:*"]
      Resource = "*"
    }]
  })
}
resource "aws_iam_role_policy" "game_lift_policy_role_1" {
  name = "GameLiftPolicy"
  role = aws_iam_role.gomoku_game_match_request.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["gamelift:*"]
      Resource = "*"
    }]
  })
}
resource "aws_iam_role_policy" "game_lift_policy_role_2" {
  name = "GameLiftPolicy"
  role = aws_iam_role.gomoku_game_match_status.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["gamelift:*"]
      Resource = "*"
    }]
  })
}
resource "aws_iam_role_policy_attachment" "gomoku_game_sqs_process_0" {
  role       = aws_iam_role.gomoku_game_sqs_process.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSQSFullAccess"
}
resource "aws_iam_role_policy_attachment" "gomoku_game_sqs_process_1" {
  role       = aws_iam_role.gomoku_game_sqs_process.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}
resource "aws_iam_role_policy_attachment" "gomoku_game_sqs_process_2" {
  role       = aws_iam_role.gomoku_game_sqs_process.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
resource "aws_iam_role_policy_attachment" "gomoku_game_rank_update_0" {
  role       = aws_iam_role.gomoku_game_rank_update.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonVPCFullAccess"
}
resource "aws_iam_role_policy_attachment" "gomoku_game_rank_update_1" {
  role       = aws_iam_role.gomoku_game_rank_update.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}
resource "aws_iam_role_policy_attachment" "gomoku_game_rank_update_2" {
  role       = aws_iam_role.gomoku_game_rank_update.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
resource "aws_iam_role_policy_attachment" "gomoku_game_rank_reader_0" {
  role       = aws_iam_role.gomoku_game_rank_reader.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonVPCFullAccess"
}
resource "aws_iam_role_policy_attachment" "gomoku_game_rank_reader_1" {
  role       = aws_iam_role.gomoku_game_rank_reader.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
resource "aws_iam_role_policy_attachment" "gomoku_game_match_status_0" {
  role       = aws_iam_role.gomoku_game_match_status.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
resource "aws_iam_role_policy_attachment" "gomoku_game_match_status_1" {
  role       = aws_iam_role.gomoku_game_match_status.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}
resource "aws_iam_role_policy_attachment" "gomoku_game_match_request_0" {
  role       = aws_iam_role.gomoku_game_match_request.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}
resource "aws_iam_role_policy_attachment" "gomoku_game_match_request_1" {
  role       = aws_iam_role.gomoku_game_match_request.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
resource "aws_iam_role_policy_attachment" "gomoku_game_lift_fleet_role" {
  role       = aws_iam_role.gomoku_game_lift_fleet_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSQSFullAccess"
}
resource "aws_iam_role_policy_attachment" "gomoku_game_match_event_0" {
  role       = aws_iam_role.gomoku_game_match_event.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}
resource "aws_iam_role_policy_attachment" "gomoku_game_match_event_1" {
  role       = aws_iam_role.gomoku_game_match_event.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
resource "aws_api_gateway_integration" "gomoku_api_ranking_get" {
  rest_api_id             = aws_api_gateway_rest_api.gomoku_api.id
  resource_id             = aws_api_gateway_resource.gomoku_api_ranking_resource.id
  http_method             = "GET"
  type                    = "AWS"
  integration_http_method = "POST"
  uri                     = "arn:aws:apigateway:${data.aws_region.current.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.game_rank_reader.arn}/invocations"
}
resource "aws_api_gateway_method_response" "gomoku_api_ranking_get" {
  rest_api_id = aws_api_gateway_rest_api.gomoku_api.id
  resource_id = aws_api_gateway_resource.gomoku_api_ranking_resource.id
  http_method = "GET"
  status_code = 200
}
resource "aws_api_gateway_integration" "gomoku_api_ranking_options" {
  rest_api_id             = aws_api_gateway_rest_api.gomoku_api.id
  resource_id             = aws_api_gateway_resource.gomoku_api_ranking_resource.id
  http_method             = "OPTIONS"
  type                    = "MOCK"
  integration_http_method = "OPTIONS"
  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}
resource "aws_api_gateway_method_response" "gomoku_api_ranking_options" {
  rest_api_id = aws_api_gateway_rest_api.gomoku_api.id
  resource_id = aws_api_gateway_resource.gomoku_api_ranking_resource.id
  http_method = "OPTIONS"
  status_code = 200
}
resource "aws_api_gateway_integration" "gomoku_api_match_request_post" {
  rest_api_id             = aws_api_gateway_rest_api.gomoku_api.id
  resource_id             = aws_api_gateway_resource.gomoku_api_match_request_resource.id
  http_method             = "POST"
  type                    = "AWS"
  integration_http_method = "POST"
  uri                     = "arn:aws:apigateway:${data.aws_region.current.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.game_match_request.arn}/invocations"
}
resource "aws_api_gateway_method_response" "gomoku_api_match_request_post" {
  rest_api_id = aws_api_gateway_rest_api.gomoku_api.id
  resource_id = aws_api_gateway_resource.gomoku_api_match_request_resource.id
  http_method = "POST"
  status_code = 200
}
resource "aws_api_gateway_integration" "gomoku_api_match_request_options" {
  rest_api_id             = aws_api_gateway_rest_api.gomoku_api.id
  resource_id             = aws_api_gateway_resource.gomoku_api_match_request_resource.id
  http_method             = "OPTIONS"
  type                    = "MOCK"
  integration_http_method = "OPTIONS"
  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}
resource "aws_api_gateway_method_response" "gomoku_api_match_request_options" {
  rest_api_id = aws_api_gateway_rest_api.gomoku_api.id
  resource_id = aws_api_gateway_resource.gomoku_api_match_request_resource.id
  http_method = "OPTIONS"
  status_code = 200
}
resource "aws_api_gateway_integration" "gomoku_api_match_status_post" {
  rest_api_id             = aws_api_gateway_rest_api.gomoku_api.id
  resource_id             = aws_api_gateway_resource.gomoku_api_match_status_resource.id
  http_method             = "POST"
  type                    = "AWS"
  integration_http_method = "POST"
  uri                     = "arn:aws:apigateway:${data.aws_region.current.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.game_match_status.arn}/invocations"
}
resource "aws_api_gateway_method_response" "gomoku_api_match_status_post" {
  rest_api_id = aws_api_gateway_rest_api.gomoku_api.id
  resource_id = aws_api_gateway_resource.gomoku_api_match_status_resource.id
  http_method = "POST"
  status_code = 200
}
resource "aws_api_gateway_integration" "gomoku_api_match_status_options" {
  rest_api_id             = aws_api_gateway_rest_api.gomoku_api.id
  resource_id             = aws_api_gateway_resource.gomoku_api_match_status_resource.id
  http_method             = "OPTIONS"
  type                    = "MOCK"
  integration_http_method = "OPTIONS"
  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}
resource "aws_api_gateway_method_response" "gomoku_api_match_status_options" {
  rest_api_id = aws_api_gateway_rest_api.gomoku_api.id
  resource_id = aws_api_gateway_resource.gomoku_api_match_status_resource.id
  http_method = "OPTIONS"
  status_code = 200
}
resource "aws_iam_role_policy" "game_lift_build_role" {
  name = "GameLiftBuildPolicy"
  role = aws_iam_role.game_lift_build_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:GetObjectVersion", "s3:*Object*"]
      Resource = ["${aws_s3_bucket.game_source_s3_bucket.arn}/*"]
    }]
  })
}
resource "aws_iam_role_policy_attachment" "windows_ec2_iam_role" {
  role       = aws_iam_role.windows_ec2_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
resource "aws_iam_role_policy" "secret_plaintext_lambda_role" {
  name = "SecretsManagerPolicy"
  role = aws_iam_role.secret_plaintext_lambda_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = "*"
    }]
  })
}
resource "aws_iam_role_policy_attachment" "secret_plaintext_lambda_role" {
  role       = aws_iam_role.secret_plaintext_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
data "archive_file" "secret_plaintext_lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda_src/secret_plaintext_lambda/index.py"
  output_path = "${path.module}/build/secret_plaintext_lambda.zip"
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
resource "aws_s3_bucket" "game_source_s3_bucket" {}
resource "aws_s3_bucket" "web_s3_bucket" {}
resource "aws_s3_bucket_policy" "web_s3_bucket_policy" {
  policy = jsonencode({
    Id      = "WebS3BucketPolicy"
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.web_s3_bucket.arn}/*"
    }]
  })
  bucket = aws_s3_bucket.web_s3_bucket.id
}
resource "aws_dynamodb_table" "gomoku_player_info" {
  name = "GomokuPlayerInfo"
  attribute {
    name = "PlayerName"
    type = "S"
  }
  billing_mode     = "PAY_PER_REQUEST"
  hash_key         = "PlayerName"
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"
}
resource "aws_elasticache_cluster" "gomoku_ranking" {
  cluster_id         = "gomokuranking"
  port               = 6379
  node_type          = "cache.r7g.large"
  engine             = "redis"
  engine_version     = 7.1
  num_cache_nodes    = 1
  subnet_group_name  = aws_elasticache_subnet_group.gomoku_ranking_subnet_group.id
  security_group_ids = [aws_security_group.gomoku_default.id]
}
resource "aws_elasticache_subnet_group" "gomoku_ranking_subnet_group" {
  description = "Subnet Group"
  subnet_ids  = [aws_subnet.public_subneta.id, aws_subnet.public_subnetc.id, aws_subnet.private_subneta.id, aws_subnet.private_subnetc.id]
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  name = "${var.stack_name}-gomoku-ranking-subnet-group"
}
resource "aws_security_group" "gomoku_default" {
  name        = "GomokuDefault"
  description = "Security Group for Gomoku Resources"
  vpc_id      = aws_vpc.vpc.id
}
resource "aws_vpc_security_group_ingress_rule" "gomoku_default_ingress" {
  security_group_id            = aws_security_group.gomoku_default.id
  ip_protocol                  = "tcp"
  from_port                    = 0
  to_port                      = 65535
  referenced_security_group_id = aws_security_group.gomoku_default.id
}
resource "aws_sqs_queue" "game_result_queue" {
  name                       = "game-result-queue"
  visibility_timeout_seconds = 60
}
resource "aws_iam_policy" "game_lift_policy" {
  name = "GameLiftPolicy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["gamelift:*"]
      Resource = "*"
    }]
  })
}
resource "aws_iam_role" "gomoku_game_sqs_process" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["lambda.amazonaws.com"]
      }
      Action = ["sts:AssumeRole"]
    }]
  })
}
resource "aws_iam_role" "gomoku_game_rank_update" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["lambda.amazonaws.com"]
      }
      Action = ["sts:AssumeRole"]
    }]
  })
}
resource "aws_iam_role" "gomoku_game_rank_reader" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["lambda.amazonaws.com"]
      }
      Action = ["sts:AssumeRole"]
    }]
  })
}
resource "aws_iam_role" "gomoku_game_match_status" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["lambda.amazonaws.com"]
      }
      Action = ["sts:AssumeRole"]
    }]
  })
}
resource "aws_iam_role" "gomoku_game_match_request" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["lambda.amazonaws.com"]
      }
      Action = ["sts:AssumeRole"]
    }]
  })
}
resource "aws_iam_role" "gomoku_game_lift_fleet_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["gamelift.amazonaws.com"]
      }
      Action = ["sts:AssumeRole"]
    }]
  })
}
resource "aws_iam_role" "gomoku_game_match_event" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["lambda.amazonaws.com"]
      }
      Action = ["sts:AssumeRole"]
    }]
  })
}
resource "aws_lambda_function" "game_sqs_process" {
  function_name = "game-sqs-process"
  runtime       = "python3.13"
  handler       = "GameResultProcessing.lambda_handler"
  role          = aws_iam_role.gomoku_game_sqs_process.arn
  timeout       = 60
  s3_bucket     = aws_s3_bucket.game_source_s3_bucket.id
  s3_key        = "Lambda/code.zip"
  depends_on    = [aws_instance.windows_ec2]
}
resource "aws_lambda_event_source_mapping" "game_sqs_process_sqs_trigger" {
  event_source_arn = aws_sqs_queue.game_result_queue.arn
  function_name    = aws_lambda_function.game_sqs_process.arn
}
resource "aws_lambda_function" "game_rank_update" {
  function_name = "game-rank-update"
  runtime       = "python3.13"
  handler       = "Scoring.handler"
  role          = aws_iam_role.gomoku_game_rank_update.arn
  timeout       = 60
  environment {
    variables = {
      REDIS = aws_elasticache_cluster.gomoku_ranking.cache_nodes[0].address
    }
  }
  vpc_config {
    security_group_ids = [aws_security_group.gomoku_default.id]
    subnet_ids         = [aws_subnet.public_subneta.id, aws_subnet.public_subnetc.id, aws_subnet.private_subneta.id, aws_subnet.private_subnetc.id]
  }
  s3_bucket  = aws_s3_bucket.game_source_s3_bucket.id
  s3_key     = "Lambda/code.zip"
  depends_on = [aws_instance.windows_ec2]
}
resource "aws_lambda_event_source_mapping" "game_rank_update_dynamo_db_trigger" {
  event_source_arn  = aws_dynamodb_table.gomoku_player_info.stream_arn
  function_name     = aws_lambda_function.game_rank_update.arn
  starting_position = "TRIM_HORIZON"
}
resource "aws_lambda_function" "game_rank_reader" {
  function_name = "game-rank-reader"
  runtime       = "python3.13"
  handler       = "GetRank.handler"
  role          = aws_iam_role.gomoku_game_rank_reader.arn
  timeout       = 60
  environment {
    variables = {
      REDIS = aws_elasticache_cluster.gomoku_ranking.cache_nodes[0].address
    }
  }
  vpc_config {
    security_group_ids = [aws_security_group.gomoku_default.id]
    subnet_ids         = [aws_subnet.public_subneta.id, aws_subnet.public_subnetc.id, aws_subnet.private_subneta.id, aws_subnet.private_subnetc.id]
  }
  s3_bucket  = aws_s3_bucket.game_source_s3_bucket.id
  s3_key     = "Lambda/code.zip"
  depends_on = [aws_instance.windows_ec2]
}
resource "aws_lambda_permission" "game_rank_reader_permission" {
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.game_rank_reader.function_name
  principal      = "apigateway.amazonaws.com"
  source_account = data.aws_caller_identity.current.account_id
  source_arn     = "arn:aws:execute-api:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:${aws_api_gateway_rest_api.gomoku_api.id}/*/GET/ranking"
}
resource "aws_lambda_function" "game_match_request" {
  function_name = "game-match-request"
  runtime       = "python3.13"
  handler       = "MatchRequest.lambda_handler"
  role          = aws_iam_role.gomoku_game_match_request.arn
  timeout       = 60
  s3_bucket     = aws_s3_bucket.game_source_s3_bucket.id
  s3_key        = "Lambda/code.zip"
  depends_on    = [aws_instance.windows_ec2]
}
resource "aws_lambda_permission" "game_match_request_permission" {
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.game_match_request.function_name
  principal      = "apigateway.amazonaws.com"
  source_account = data.aws_caller_identity.current.account_id
  source_arn     = "arn:aws:execute-api:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:${aws_api_gateway_rest_api.gomoku_api.id}/*/POST/matchrequest"
}
resource "aws_lambda_function" "game_match_status" {
  function_name = "game-match-status"
  runtime       = "python3.13"
  handler       = "MatchStatus.lambda_handler"
  role          = aws_iam_role.gomoku_game_match_status.arn
  timeout       = 60
  s3_bucket     = aws_s3_bucket.game_source_s3_bucket.id
  s3_key        = "Lambda/code.zip"
  depends_on    = [aws_instance.windows_ec2]
}
resource "aws_lambda_permission" "game_match_status_permission" {
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.game_match_status.function_name
  principal      = "apigateway.amazonaws.com"
  source_account = data.aws_caller_identity.current.account_id
  source_arn     = "arn:aws:execute-api:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:${aws_api_gateway_rest_api.gomoku_api.id}/*/POST/matchstatus"
}
resource "aws_lambda_function" "game_match_event" {
  function_name = "game-match-event"
  runtime       = "python3.13"
  handler       = "MatchEvent.lambda_handler"
  role          = aws_iam_role.gomoku_game_match_event.arn
  timeout       = 60
  s3_bucket     = aws_s3_bucket.game_source_s3_bucket.id
  s3_key        = "Lambda/code.zip"
  depends_on    = [aws_instance.windows_ec2]
}
resource "aws_lambda_permission" "game_match_event_permission" {
  function_name = aws_lambda_function.game_match_event.arn
  action        = "lambda:InvokeFunction"
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.sns_topic.arn
}
resource "aws_sns_topic" "sns_topic" {
  name = "gomoku-match-topic"
}
resource "aws_sns_topic_policy" "sns_topic_access_policy" {
  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "SnsTopicPolicy"
    Statement = [{
      Sid    = "AllowSnsActions"
      Effect = "Allow"
      Principal = {
        AWS = "*"
      }
      Action   = ["SNS:GetTopicAttributes", "SNS:SetTopicAttributes", "SNS:AddPermission", "SNS:RemovePermission", "SNS:DeleteTopic", "SNS:Subscribe", "SNS:ListSubscriptionsByTopic", "SNS:Publish"]
      Resource = "arn:aws:sns:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:${aws_sns_topic.sns_topic.name}"
      Condition = {
        StringEquals = {
          "AWS:SourceOwner" = data.aws_caller_identity.current.account_id
        }
      }
      }, {
      Sid    = "AllowSnsPublish"
      Effect = "Allow"
      Principal = {
        Service = "gamelift.amazonaws.com"
      }
      Action   = "SNS:Publish"
      Resource = "arn:aws:sns:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:${aws_sns_topic.sns_topic.name}"
    }]
  })
  # A single topic ARN string, not the list CloudFormation's
  # AWS::SNS::TopicPolicy Topics property takes - the same list-to-scalar
  # mistake rules.md A-3 describes for aws_iam_instance_profile.role. The
  # attribute is a string either way, so validate and plan pass and the
  # failure only shows up as an SNS API error during apply.
  arn = aws_sns_topic.sns_topic.arn
}
resource "aws_sns_topic_subscription" "sns_subscription" {
  protocol  = "lambda"
  endpoint  = aws_lambda_function.game_match_event.arn
  topic_arn = aws_sns_topic.sns_topic.arn
}
resource "aws_api_gateway_rest_api" "gomoku_api" {
  name = "GomokuAPI"
  endpoint_configuration {
    types = ["REGIONAL"]
  }
}
resource "aws_api_gateway_resource" "gomoku_api_ranking_resource" {
  rest_api_id = aws_api_gateway_rest_api.gomoku_api.id
  parent_id   = aws_api_gateway_rest_api.gomoku_api.root_resource_id
  path_part   = "ranking"
}
resource "aws_api_gateway_method" "gomoku_api_ranking_get" {
  authorization = "NONE"
  http_method   = "GET"
  resource_id   = aws_api_gateway_resource.gomoku_api_ranking_resource.id
  rest_api_id   = aws_api_gateway_rest_api.gomoku_api.id
}
resource "aws_api_gateway_method" "gomoku_api_ranking_options" {
  authorization = "NONE"
  http_method   = "OPTIONS"
  resource_id   = aws_api_gateway_resource.gomoku_api_ranking_resource.id
  rest_api_id   = aws_api_gateway_rest_api.gomoku_api.id
}
resource "aws_api_gateway_resource" "gomoku_api_match_request_resource" {
  rest_api_id = aws_api_gateway_rest_api.gomoku_api.id
  parent_id   = aws_api_gateway_rest_api.gomoku_api.root_resource_id
  path_part   = "matchrequest"
}
resource "aws_api_gateway_method" "gomoku_api_match_request_post" {
  authorization = "NONE"
  http_method   = "POST"
  resource_id   = aws_api_gateway_resource.gomoku_api_match_request_resource.id
  rest_api_id   = aws_api_gateway_rest_api.gomoku_api.id
}
resource "aws_api_gateway_method" "gomoku_api_match_request_options" {
  authorization = "NONE"
  http_method   = "OPTIONS"
  resource_id   = aws_api_gateway_resource.gomoku_api_match_request_resource.id
  rest_api_id   = aws_api_gateway_rest_api.gomoku_api.id
}
resource "aws_api_gateway_resource" "gomoku_api_match_status_resource" {
  rest_api_id = aws_api_gateway_rest_api.gomoku_api.id
  parent_id   = aws_api_gateway_rest_api.gomoku_api.root_resource_id
  path_part   = "matchstatus"
}
resource "aws_api_gateway_method" "gomoku_api_match_status_post" {
  authorization = "NONE"
  http_method   = "POST"
  resource_id   = aws_api_gateway_resource.gomoku_api_match_status_resource.id
  rest_api_id   = aws_api_gateway_rest_api.gomoku_api.id
}
resource "aws_api_gateway_method" "gomoku_api_match_status_options" {
  authorization = "NONE"
  http_method   = "OPTIONS"
  resource_id   = aws_api_gateway_resource.gomoku_api_match_status_resource.id
  rest_api_id   = aws_api_gateway_rest_api.gomoku_api.id
}
resource "aws_api_gateway_deployment" "gomoku_api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.gomoku_api.id
  depends_on  = [aws_api_gateway_method.gomoku_api_ranking_get, aws_api_gateway_method.gomoku_api_ranking_options, aws_api_gateway_method.gomoku_api_match_request_post, aws_api_gateway_method.gomoku_api_match_request_options, aws_api_gateway_method.gomoku_api_match_status_post, aws_api_gateway_method.gomoku_api_match_status_options]
}
resource "aws_iam_role" "game_lift_build_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["cloudformation.amazonaws.com", "gamelift.amazonaws.com"]
      }
      Action = "sts:AssumeRole"
    }]
  })
}
resource "aws_gamelift_build" "game_lift_build" {
  name             = "GomokuServer-Build-1"
  operating_system = "WINDOWS_2016"
  storage_location {
    bucket   = aws_s3_bucket.game_source_s3_bucket.id
    key      = "server.zip"
    role_arn = aws_iam_role.game_lift_build_role.arn
  }
  depends_on = [aws_instance.windows_ec2]
}
resource "aws_gamelift_fleet" "game_lift_fleet" {
  name     = "GomokuGameServerFleet-1"
  build_id = aws_gamelift_build.game_lift_build.id
  ec2_inbound_permission {
    from_port = 49152
    to_port   = 60000
    ip_range  = "0.0.0.0/0"
    protocol  = "TCP"
  }
  ec2_instance_type = "c5.large"
  fleet_type        = "SPOT"
  instance_role_arn = aws_iam_role.gomoku_game_lift_fleet_role.arn
  runtime_configuration {
    game_session_activation_timeout_seconds = 600
    max_concurrent_game_session_activations = 2147483647
    server_process {
      concurrent_executions = 50
      launch_path           = "C:\\game\\Binaries\\Win64\\GomokuServer.exe"
    }
  }
}
resource "aws_gamelift_alias" "game_lift_alias" {
  name = "GomokuAlias"
  routing_strategy {
    type     = "SIMPLE"
    fleet_id = aws_gamelift_fleet.game_lift_fleet.id
  }
}
resource "aws_gamelift_game_session_queue" "game_lift_queue" {
  name               = "gomoku-queue"
  timeout_in_seconds = 600
  destinations       = [aws_gamelift_alias.game_lift_alias.arn]
}
# === GameLiftMatchmakingRuleSet (AWS::GameLift::MatchmakingRuleSet) NOT CONVERTED ===
# Not implemented by the AWS provider (no aws_gamelift_matchmaking_rule_set resource).
# Original CloudFormation definition:
# # {
# #   "Type": "AWS::GameLift::MatchmakingRuleSet",
# #   "Properties": {
# #     "Name": "gomoku-matchmaking-rule",
# #     "RuleSetBody": {
# #       "Fn::Sub": "{\n    \"ruleLanguageVersion\" : \"1.0\",\n    \"playerAttributes\" :\n    [\n        {\n            \"name\" : \"score\",\n            \"type\" : \"number\",\n            \"default\" : 1000\n        }\n    ],\n    \"teams\" :\n    [\n        {\n            \"name\" : \"blue\",\n            \"maxPlayers\" : 1,\n            \"minPlayers\" : 1\n        },\n        {\n            \"name\" : \"red\",\n            \"maxPlayers\" : 1,\n            \"minPlayers\" : 1\n        }\n    ],\n    \"rules\" :\n    [\n        {   \"name\": \"EqualTeamSizes\",\n            \"type\": \"comparison\",\n            \"measurements\": [ \"count(teams[red].players)\" ],\n            \"referenceValue\": \"count(teams[blue].players)\",\n            \"operation\": \"=\"\n        },\n        {\n            \"name\" : \"FairTeamSkill\",\n            \"type\" : \"distance\",\n            \"measurements\" : [ \"avg(teams[*].players.attributes[score])\" ],\n            \"referenceValue\" : \"avg(flatten(teams[*].players.attributes[score]))\",\n            \"maxDistance\" : 300\n        }\n    ],\n    \"expansions\" :\n    [\n        {\n            \"target\" : \"rules[FairTeamSkill].maxDistance\",\n            \"steps\" :\n            [\n                {\n                    \"waitTimeSeconds\" : 10,\n                    \"value\" : 500\n                },\n                {\n                    \"waitTimeSeconds\" : 20,\n                    \"value\" : 800\n                },\n                {\n                    \"waitTimeSeconds\" : 30,\n                    \"value\" : 1000\n                }\n            ]\n        }\n    ]\n}\n"
# #     }
# #   }
# # }
# === GameLiftMatchmakingConfiguration (AWS::GameLift::MatchmakingConfiguration) NOT CONVERTED ===
# Not implemented by the AWS provider (no aws_gamelift_matchmaking_configuration resource).
# Original CloudFormation definition:
# # {
# #   "Type": "AWS::GameLift::MatchmakingConfiguration",
# #   "Properties": {
# #     "Name": "GomokuMatchConfig",
# #     "RequestTimeoutSeconds": 60,
# #     "AcceptanceRequired": false,
# #     "GameSessionQueueArns": [
# #       {
# #         "Fn::GetAtt": [
# #           "GameLiftQueue",
# #           "Arn"
# #         ]
# #       }
# #     ],
# #     "RuleSetName": {
# #       "Fn::GetAtt": [
# #         "GameLiftMatchmakingRuleSet",
# #         "Name"
# #       ]
# #     },
# #     "NotificationTarget": {
# #       "Fn::GetAtt": [
# #         "SnsTopic",
# #         "TopicArn"
# #       ]
# #     }
# #   }
# # }
# CreationPolicy: CloudFormation CreationPolicy (cfn-signal) has no Terraform equivalent; the wait is not reproduced.
# # {
# #   "ResourceSignal": {
# #     "Count": "1",
# #     "Timeout": "PT30M"
# #   }
# # }
resource "aws_instance" "windows_ec2" {
  ami           = data.aws_ssm_parameter.windows_server_ami_id.insecure_value
  instance_type = "m5.2xlarge"
  key_name      = aws_key_pair.key_pair.key_name
  tags = {
    Name = "windows"
  }
  iam_instance_profile        = aws_iam_instance_profile.windows_ec2_instance_profile.name
  user_data                   = <<EOT
<powershell>
$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"
$LogFile = "C:\ProgramData\GameliftWorkshop\setup.log"
New-Item -ItemType Directory -Path "C:\ProgramData\GameliftWorkshop" -Force

function Write-Log {
    param([string]$Message)
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "[$Timestamp] $Message"
    Write-Host $LogMessage
    Add-Content -Path $LogFile -Value $LogMessage -ErrorAction SilentlyContinue
}

Write-Log "Starting Gamelift Workshop Windows Setup"

try {
    # Install AWS PowerShell Module
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers
    Install-Module -Name AWS.Tools.SecretsManager -Force -AllowClobber -Scope AllUsers
    Import-Module AWS.Tools.SecretsManager -Force
    Set-DefaultAWSRegion -Region ${data.aws_region.current.region}

    $SecretValue = Get-SECSecretValue -SecretId ${aws_secretsmanager_secret.windows_user_password.id} -Region ${data.aws_region.current.region}
    $WorkshopPassword = ($SecretValue.SecretString | ConvertFrom-Json).password
    Write-Log "Password Retrieved"

    # Restrict Windows dynamic (ephemeral) port range to match the GameLift Fleet's
    # EC2InboundPermissions (49152-60000). GameLift Windows fleets only support port
    # ranges up to 60000, but Windows Server's default ephemeral range extends to 65535.
    # Without this, GameLift server processes that bind to a port above 60000 will fail
    # ProcessReady() and exit (SERVER_PROCESS_CRASHED).
    Write-Log "Restricting dynamic port range to 49152-60000"
    netsh int ipv4 set dynamicport tcp start=49152 num=10849
    netsh int ipv6 set dynamicport tcp start=49152 num=10849

    # Enable RDP
    Write-Log "Configuring RDP"
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0 -Force
    Set-Service -Name "TermService" -StartupType Automatic
    Start-Service -Name "TermService" -ErrorAction SilentlyContinue
    netsh advfirewall firewall set rule group="Remote Desktop" new enable=yes

    # Create Workshop User
    Write-Log "Creating Workshop User"
    Remove-LocalUser -Name "${var.username}" -ErrorAction SilentlyContinue
    $Password = ConvertTo-SecureString $WorkshopPassword -AsPlainText -Force
    $User = New-LocalUser -Name "${var.username}" -Password $Password -FullName "Workshop User" -PasswordNeverExpires -AccountNeverExpires
    Add-LocalGroupMember -Group "Administrators" -Member "${var.username}" -ErrorAction SilentlyContinue
    Add-LocalGroupMember -Group "Remote Desktop Users" -Member "${var.username}" -ErrorAction SilentlyContinue

    # Setup Directories - Enhanced domain handling
    Write-Log "Finding Workshop User Profile"
    $UserProfiles = Get-WmiObject -Class Win32_UserProfile | Where-Object {
        $_.LocalPath -like "*${var.username}*" -and
        $_.LocalPath -notlike "*.bak" -and
        $_.LocalPath -notlike "*temp*"
    }

    if ($UserProfiles) {
        # Find workshop.ComputerName Pattern Specifically
        $ComputerName = $env:COMPUTERNAME
        $PreferredPattern = "${var.username}.$ComputerName"

        $PreferredProfile = $UserProfiles | Where-Object {$_.LocalPath -like "*$PreferredPattern*" -and $_.LocalPath -notlike "*.000" -and $_.LocalPath -notlike "*.001"}

        if ($PreferredProfile) {
            $UserProfilePath = $PreferredProfile[0].LocalPath
            Write-Log "Selected Preferred Profile: $UserProfilePath"
        } else {
            # Fallback to the shortest Path
            $UserProfilePath = ($UserProfiles.LocalPath | Sort-Object Length)[0]
            Write-Log "Selected Fallback Profile: $UserProfilePath"
        }

        # Log all found Profiles for Debugging
        foreach ($profile in $UserProfiles) {
            Write-Log "Found ${var.username} Profile: $($profile.LocalPath)"
        }
    } else {
        # Deterministically Construct workshop.ComputerName Path
        $ComputerName = $env:COMPUTERNAME
        $UserProfilePath = "C:\Users\${var.username}.$ComputerName"
        Write-Log "Using Constructed Path: $UserProfilePath"
    }

    $WorkshopDir = "C:\ProgramData\GameliftWorkshop"
    $TempDir = "$WorkshopDir\temp"
    New-Item -ItemType Directory -Path $TempDir -Force

    # Install Chocolatey
    Write-Log "Installing Chocolatey"
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

    Write-Log "Installing Git"
    choco install git -y

    Write-Log "Installing AWS CLI"
    choco install awscli -y

    Write-Log "Installing Python 3.14"
    choco install python314 -y

    # Refresh Environment Variables after Installations
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

    try {
        $awsVersion = aws --version
        Write-Log "AWS CLI Installed: $awsVersion"
    } catch {
        Write-Log "AWS CLI Verification Failed"
    }

    # Set Permissions
    icacls $WorkshopDir /grant "${var.username}:F" /T /Q
    if (Test-Path $UserProfilePath) {
        icacls "$UserProfilePath" /grant "${var.username}:F" /T /Q
    }

    $maxRetries = 10
    $retryCount = 0
    do {
        Start-Sleep -Seconds 3
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        $gitAvailable = Get-Command git -ErrorAction SilentlyContinue
        $retryCount++
    } while (-not $gitAvailable -and $retryCount -lt $maxRetries)

    if ($gitAvailable) {
        $gitVersion = git --version
        Write-Log "Git installed: $gitVersion"
        Set-Location $WorkshopDir
        git clone https://github.com/iamhansko/aws-gamelift-sample.git
    } else {
        Write-Log "Git Unavailable"
    }

    Set-Location $WorkshopDir\aws-gamelift-sample
    @'
[config]
# GameResult SQS
SQS_REGION = ${data.aws_region.current.region}
SQS_ENDPOINT = ${aws_sqs_queue.game_result_queue.url}
ROLE_ARN = ${aws_iam_role.gomoku_game_lift_fleet_role.arn}
'@ | Out-File -FilePath $WorkshopDir\aws-gamelift-sample\bin\FlexMatch\GomokuServer\Binaries\Win64\config.ini -Encoding ascii
    Set-Location $WorkshopDir\aws-gamelift-sample\bin\FlexMatch\GomokuServer
    Compress-Archive -Path .\* -DestinationPath .\server.zip -Force
    aws s3 cp .\server.zip s3://${aws_s3_bucket.game_source_s3_bucket.id}/server.zip
    Set-Location $WorkshopDir\aws-gamelift-sample
    aws s3 cp --recursive $WorkshopDir\aws-gamelift-sample s3://${aws_s3_bucket.game_source_s3_bucket.id}

    (Get-Content $WorkshopDir\aws-gamelift-sample\web\main.js) -replace 'niop6gw2v0', '${aws_api_gateway_rest_api.gomoku_api.id}' | Set-Content $WorkshopDir\aws-gamelift-sample\web\main.js
    (Get-Content $WorkshopDir\aws-gamelift-sample\web\main.js) -replace 'us-east-1', '${data.aws_region.current.region}' | Set-Content $WorkshopDir\aws-gamelift-sample\web\main.js
    aws s3 cp --recursive $WorkshopDir\aws-gamelift-sample\web\ s3://${aws_s3_bucket.web_s3_bucket.id}

    Set-Location $WorkshopDir\aws-gamelift-sample\bin\FlexMatch

    @'
[config]
MATCH_SERVER_API = https://${aws_api_gateway_rest_api.gomoku_api.id}.execute-api.${data.aws_region.current.region}.amazonaws.com/prod
PLAYER_NAME = Amazonian
PLAYER_PASSWD = simplepw00
'@ | Out-File -FilePath $WorkshopDir\aws-gamelift-sample\bin\FlexMatch\Client_player1\config.ini -Encoding ascii

    @'
[config]
MATCH_SERVER_API = https://${aws_api_gateway_rest_api.gomoku_api.id}.execute-api.${data.aws_region.current.region}.amazonaws.com/prod
PLAYER_NAME = Ahro
PLAYER_PASSWD = simplepw00
'@ | Out-File -FilePath $WorkshopDir\aws-gamelift-sample\bin\FlexMatch\Client_player2\config.ini -Encoding ascii

    Compress-Archive -Path $WorkshopDir\aws-gamelift-sample\bin\FlexMatch\Client_player1, $WorkshopDir\aws-gamelift-sample\bin\FlexMatch\Client_player2 -DestinationPath "$WorkshopDir\aws-gamelift-sample\client.zip" -Force
    aws s3 cp "$WorkshopDir\aws-gamelift-sample\client.zip" s3://${aws_s3_bucket.game_source_s3_bucket.id}/client.zip

    Write-Log "Creating Workshop User Logon Script"
    $LogonScript = '# Workshop User First Logon Setup' + "`n"
    $LogonScript += '$LogFile = "C:\ProgramData\GameliftWorkshop\logon.log"' + "`n"
    $LogonScript += 'function Write-LogonLog { param([string]$Message); Add-Content -Path $LogFile -Value "[$((Get-Date))] $Message" }' + "`n"
    $LogonScript += '$DesktopPath = [Environment]::GetFolderPath("Desktop")' + "`n"
    $LogonScript += 'Write-LogonLog "Desktop path: $DesktopPath"' + "`n"
    $LogonScript += '$GameClientPath = "C:\ProgramData\GameliftWorkshop\aws-gamelift-sample\bin\FlexMatch"' + "`n"
    $LogonScript += '$WshShell = New-Object -comObject WScript.Shell' + "`n"
    $LogonScript += 'if (Test-Path "C:\ProgramData\GameliftWorkshop\aws-gamelift-sample\bin\FlexMatch\Client_player1") {' + "`n"
    $LogonScript += '    $GameClient1Shortcut = $WshShell.CreateShortcut("$DesktopPath\Game Client 1.lnk")' + "`n"
    $LogonScript += '    $GameClient1Shortcut.TargetPath = "$GameClientPath\Client_player1"' + "`n"
    $LogonScript += '    $GameClient1Shortcut.Save()' + "`n"
    $LogonScript += '    Write-LogonLog "Game Client 1 Shortcut Created"' + "`n"
    $LogonScript += '}' + "`n"
    $LogonScript += 'if (Test-Path "C:\ProgramData\GameliftWorkshop\aws-gamelift-sample\bin\FlexMatch\Client_player2") {' + "`n"
    $LogonScript += '    $GameClient2Shortcut = $WshShell.CreateShortcut("$DesktopPath\Game Client 2.lnk")' + "`n"
    $LogonScript += '    $GameClient2Shortcut.TargetPath = "$GameClientPath\Client_player2"' + "`n"
    $LogonScript += '    $GameClient2Shortcut.Save()' + "`n"
    $LogonScript += '    Write-LogonLog "Game Client 2 Shortcut Created"' + "`n"
    $LogonScript += '}' + "`n"
    $LogonScript += 'Write-LogonLog "Workshop User Setup Completed"' + "`n"
    $LogonScript += 'Remove-Item $MyInvocation.MyCommand.Path -Force' + "`n"

    $LogonScriptPath = "C:\ProgramData\GameliftWorkshop\${var.username}-setup.ps1"
    Set-Content -Path $LogonScriptPath -Value $LogonScript
    $LogonKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
    Set-ItemProperty -Path $LogonKey -Name "WorkshopSetup" -Value "powershell.exe -ExecutionPolicy Bypass -File `"$LogonScriptPath`"" -Force
} catch {
    Write-Log "Setup Failed: $($_.Exception.Message)"
    cfn-signal --success false --stack ${var.stack_name} --resource WindowsEc2 --region ${data.aws_region.current.region}
    throw
}

cfn-signal --success true --stack ${var.stack_name} --resource WindowsEc2 --region ${data.aws_region.current.region}
</powershell>
EOT
  subnet_id                   = aws_subnet.public_subneta.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.windows_ec2_security_group.id]
  root_block_device {
    volume_type           = "gp3"
    volume_size           = 100
    delete_on_termination = true
    encrypted             = false
  }
}
resource "aws_security_group" "windows_ec2_security_group" {
  description = "Security Group"
  name        = "windows-sg"
  vpc_id      = aws_vpc.vpc.id
  dynamic "ingress" {
    for_each = local.cond_security_group_inbound_from_anywhere ? [1] : []
    content {
      protocol    = "tcp"
      from_port   = 3389
      to_port     = 3389
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
  tags = {
    Name = "windows-sg"
  }
}
resource "aws_iam_role" "windows_ec2_iam_role" {
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
resource "aws_iam_instance_profile" "windows_ec2_instance_profile" {
  # An instance profile holds at most one role, so this attribute is a single
  # role name string - not the list CloudFormation's AWS::IAM::InstanceProfile
  # Roles property takes. jsonencode([...]) here sends the literal string
  # ["terraform-..."] as roleName, which IAM rejects with a ValidationError
  # during apply, while terraform validate and plan both pass because the
  # attribute is a string either way (rules.md A-3).
  role = aws_iam_role.windows_ec2_iam_role.name
}
resource "aws_secretsmanager_secret" "windows_user_password" {
  # TODO cfn2tf: unmapped CloudFormation property 'GenerateSecretString' of AWS::SecretsManager::Secret
  # # {
  # #   "SecretStringTemplate": {
  # #     "Fn::Sub": "{\"username\": \"${Username}\"}"
  # #   },
  # #   "GenerateStringKey": "password",
  # #   "PasswordLength": 20,
  # #   "ExcludeCharacters": "\"@/\\",
  # #   "RequireEachIncludedType": true,
  # #   "IncludeSpace": false
  # # }
}
resource "aws_lambda_invocation" "secret_plaintext" {
  function_name = aws_lambda_function.secret_plaintext_lambda.arn
  input = jsonencode({
    ServiceTimeout = 15
    SecretArn      = aws_secretsmanager_secret.windows_user_password.arn
  })
}
resource "aws_iam_role" "secret_plaintext_lambda_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.${data.aws_partition.current.dns_suffix}"
      }
      Action = "sts:AssumeRole"
    }]
  })
}
resource "aws_lambda_function" "secret_plaintext_lambda" {
  description      = "Return the value of the secret"
  handler          = "index.lambda_handler"
  runtime          = "python3.13"
  memory_size      = 128
  timeout          = 10
  architectures    = ["arm64"]
  role             = aws_iam_role.secret_plaintext_lambda_role.arn
  filename         = data.archive_file.secret_plaintext_lambda.output_path
  source_code_hash = data.archive_file.secret_plaintext_lambda.output_base64sha256
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  function_name = "${var.stack_name}-secret-plaintext-lambda"
}
# --- Outputs ---
# CloudFormation output: 01GameClientZipFileDownload
output "out_01_game_client_zip_file_download" {
  value = "https://${data.aws_region.current.region}.console.aws.amazon.com/s3/object/${aws_s3_bucket.game_source_s3_bucket.id}?region=${data.aws_region.current.region}&bucketType=general&prefix=client.zip"
}
# CloudFormation output: 02GomokuWeb
output "out_02_gomoku_web" {
  value       = aws_s3_bucket.web_s3_bucket.website_endpoint
  description = "Gomoku Leaderboard URL"
}
# CloudFormation output: 03GameClientAccess
output "out_03_game_client_access" {
  value       = "Computer : ${aws_instance.windows_ec2.public_ip} / Username : ${var.username} / Password : ${jsondecode(aws_lambda_invocation.secret_plaintext.result)["password"]}\n"
  description = "Connect to the Game Client (Windows) using RDP"
}
# CloudFormation output: 04GameServerAccess
output "out_04_game_server_access" {
  value       = "GAME_SERVER_INSTANCE=$(aws gamelift describe-instances --fleet-id ${aws_gamelift_fleet.game_lift_fleet.id} --output text --query 'Instances[0].InstanceId'); aws gamelift get-instance-access --fleet-id ${aws_gamelift_fleet.game_lift_fleet.id} --instance-id $GAME_SERVER_INSTANCE\n"
  description = "Connect to the Game Server (Windows) using RDP (https://docs.aws.amazon.com/gameliftservers/latest/developerguide/fleets-remote-access.html#fleets-remote-access-connect)"
}
# CloudFormation output: 05ElasticacheRedisConnect
output "out_05_elasticache_redis_connect" {
  value       = "redis6-cli -h ${aws_elasticache_cluster.gomoku_ranking.cache_nodes[0].address} -p 6379 ZRANGE Rating 0 -1 WITHSCORES\n"
  description = "Use CloudShell in the VPC"
}
