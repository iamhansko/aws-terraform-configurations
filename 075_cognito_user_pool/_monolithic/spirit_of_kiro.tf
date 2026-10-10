# Generated from 075_cognito_user_pool/spirit_of_kiro.yaml by tools/cfn2tf.
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
  default     = "spirit-of-kiro"
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
variable "environment" {
  type        = string
  default     = "dev"
  description = "Environment name (e.g., dev, prod)"
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
    EcsServiceMapping = {
      Server = {
        ContainerPort = 8080
      }
      ImageGeneration = {
        ContainerPort = 3001
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
resource "aws_iam_role_policy_attachment" "vs_code_ec2_iam_role" {
  role       = aws_iam_role.vs_code_ec2_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
resource "aws_ecs_cluster_capacity_providers" "ecs_cluster" {
  cluster_name       = aws_ecs_cluster.ecs_cluster.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]
  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
  }
}
resource "aws_iam_role_policy" "ecs_task_execution_role" {
  name = "EcrAndCloudWatchPolicy"
  role = aws_iam_role.ecs_task_execution_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ecr:GetAuthorizationToken"]
      Resource = "*"
      }, {
      Effect   = "Allow"
      Action   = ["ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage"]
      Resource = [aws_ecr_repository.server_repository.arn, aws_ecr_repository.image_generation_repository.arn]
      }, {
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = ["${aws_cloudwatch_log_group.server_log_group.arn}:*", "${aws_cloudwatch_log_group.image_generation_log_group.arn}:*"]
    }]
  })
}
resource "aws_iam_role_policy" "ecs_task_role" {
  name = "TaskPolicy"
  role = aws_iam_role.ecs_task_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:DeleteItem", "dynamodb:Query", "dynamodb:Scan", "dynamodb:BatchGetItem", "dynamodb:BatchWriteItem"]
      Resource = [aws_dynamodb_table.items_table.arn, aws_dynamodb_table.inventory_table.arn, aws_dynamodb_table.location_table.arn, aws_dynamodb_table.users_table.arn, aws_dynamodb_table.usernames_table.arn, aws_dynamodb_table.persona_table.arn]
      }, {
      Effect   = "Allow"
      Action   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
      Resource = "*"
      }, {
      Effect   = "Allow"
      Action   = ["cognito-idp:SignUp", "cognito-idp:InitiateAuth", "cognito-idp:GetUser", "cognito-idp:AdminConfirmSignUp", "cognito-idp:AdminGetUser", "cognito-idp:AdminUpdateUserAttributes"]
      Resource = aws_cognito_user_pool.user_pool.arn
      }, {
      Effect   = "Allow"
      Action   = ["s3:PutObject", "s3:GetObject", "s3:ListBucket"]
      Resource = "*"
    }]
  })
}
data "archive_file" "custom_lambda_function" {
  type        = "zip"
  source_file = "${path.module}/lambda_src/custom_lambda_function/index.py"
  output_path = "${path.module}/build/custom_lambda_function.zip"
}
resource "aws_iam_role_policy" "custom_lambda_iam_role" {
  name = "LambdaFunctionPolicy"
  role = aws_iam_role.custom_lambda_iam_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ec2:DescribeManagedPrefixLists"]
      Resource = "*"
    }]
  })
}
resource "aws_iam_role_policy_attachment" "custom_lambda_iam_role" {
  role       = aws_iam_role.custom_lambda_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
# --- Resources ---
resource "aws_cognito_user_pool" "user_pool" {
  admin_create_user_config {
    allow_admin_create_user_only = false
  }
  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
    require_uppercase = true
  }
  schema {
    name                = "email"
    attribute_data_type = "String"
    required            = true
    mutable             = true
  }
  schema {
    name                = "preferred_username"
    attribute_data_type = "String"
    required            = true
    mutable             = true
  }
  username_attributes = ["email"]
  username_configuration {
    case_sensitive = false
  }
  user_pool_add_ons {
    advanced_security_mode = "OFF"
  }
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  name = "${var.stack_name}-user-pool"
}
resource "aws_cognito_user_pool_client" "user_pool_client" {
  user_pool_id                  = aws_cognito_user_pool.user_pool.id
  generate_secret               = false
  prevent_user_existence_errors = "ENABLED"
  explicit_auth_flows           = ["USER_PASSWORD_AUTH"]
  access_token_validity         = 1
  id_token_validity             = 1
  refresh_token_validity        = 30
  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  name = "${var.stack_name}-user-pool-client"
}
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
resource "aws_ecr_repository" "server_repository" {
  force_delete = true
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  name = "${var.stack_name}-server-repository"
}
resource "aws_ecr_repository" "image_generation_repository" {
  force_delete = true
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  name = "${var.stack_name}-image-generation-repository"
}
# CreationPolicy: CloudFormation CreationPolicy (cfn-signal) has no Terraform equivalent; the wait is not reproduced.
# # {
# #   "ResourceSignal": {
# #     "Count": "1",
# #     "Timeout": "PT10M"
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
dnf install -yq git
dnf groupinstall -yq "Development Tools"

dnf install -yq git
dnf install -yq docker
systemctl enable --now docker
# usermod -aG docker ec2-user
# newgrp docker
chmod 666 /var/run/docker.sock

export VSC_VERSION="4.106.2"
wget https://github.com/coder/code-server/releases/download/v$VSC_VERSION/code-server-$VSC_VERSION-linux-amd64.tar.gz
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

cd /home/ec2-user
git clone https://github.com/iamhansko/spirit-of-kiro.git
chown -R ec2-user:ec2-user /home/ec2-user/spirit-of-kiro/

sudo -Eu ec2-user bash << 'EOF'
curl -fsSL https://bun.com/install | bash
source /home/ec2-user/.bash_profile
cd /home/ec2-user/spirit-of-kiro/client
echo "declare module '*.vue'" > ./src/shims-vue.d.ts
bun install
bun run build
EOF
aws s3 cp --recursive /home/ec2-user/spirit-of-kiro/client/dist/ s3://${aws_s3_bucket.client_bucket.id}

cd /home/ec2-user/spirit-of-kiro
aws ecr get-login-password | docker login --username AWS --password-stdin ${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.region}.amazonaws.com
docker build -t "${aws_ecr_repository.server_repository.repository_url}:latest" ./server
docker push "${aws_ecr_repository.server_repository.repository_url}:latest"
docker build -t "${aws_ecr_repository.image_generation_repository.repository_url}:latest" ./item-images
docker push "${aws_ecr_repository.image_generation_repository.repository_url}:latest"

aws iam create-service-linked-role --aws-service-name ecs.amazonaws.com || true
aws bedrock list-foundation-models --query "modelSummaries[*].modelId" > /home/ec2-user/bedrock_models.txt

/opt/aws/bin/cfn-signal -e $? --stack ${var.stack_name} --resource VsCodeEc2 --region ${data.aws_region.current.region}
EOT
  subnet_id                   = aws_subnet.public_subneta.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.vs_code_ec2_security_group.id]
  depends_on                  = [aws_cognito_user_pool_client.user_pool_client]
}
resource "aws_security_group" "vs_code_ec2_security_group" {
  description = "Security Group"
  name        = "vscode-sg"
  vpc_id      = aws_vpc.vpc.id
  dynamic "ingress" {
    for_each = local.cond_security_group_inbound_from_anywhere ? [1] : []
    content {
      protocol    = "tcp"
      from_port   = 8000
      to_port     = 8000
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
  tags = {
    Name = "vscode-sg"
  }
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
resource "aws_ecs_task_definition" "server_task_definition" {
  family                   = "server-taskdef"
  cpu                      = 1024
  memory                   = 2048
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }
  container_definitions = jsonencode([{
    Name      = "main"
    Image     = "${aws_ecr_repository.server_repository.repository_url}:latest"
    Essential = true
    PortMappings = [{
      ContainerPort = local.mappings["EcsServiceMapping"]["Server"]["ContainerPort"]
      HostPort      = local.mappings["EcsServiceMapping"]["Server"]["ContainerPort"]
      Protocol      = "tcp"
    }]
    Environment = [{
      Name  = "PORT"
      Value = local.mappings["EcsServiceMapping"]["Server"]["ContainerPort"]
      }, {
      Name  = "ENVIRONMENT"
      Value = var.environment
      }, {
      Name  = "DYNAMODB_TABLE_ITEMS"
      Value = aws_dynamodb_table.items_table.name
      }, {
      Name  = "DYNAMODB_TABLE_INVENTORY"
      Value = aws_dynamodb_table.inventory_table.name
      }, {
      Name  = "DYNAMODB_TABLE_LOCATION"
      Value = aws_dynamodb_table.location_table.name
      }, {
      Name  = "DYNAMODB_TABLE_USERS"
      Value = aws_dynamodb_table.users_table.name
      }, {
      Name  = "DYNAMODB_TABLE_USERNAMES"
      Value = aws_dynamodb_table.usernames_table.name
      }, {
      Name  = "DYNAMODB_TABLE_PERSONA"
      Value = aws_dynamodb_table.persona_table.name
      }, {
      Name  = "COGNITO_USER_POOL_ID"
      Value = aws_cognito_user_pool.user_pool.id
      }, {
      Name  = "COGNITO_CLIENT_ID"
      Value = aws_cognito_user_pool_client.user_pool_client.id
      }, {
      Name  = "ITEM_IMAGES_SERVICE_URL"
      Value = "http://${aws_lb.image_generation_alb.dns_name}"
    }]
    LogConfiguration = {
      LogDriver = "awslogs"
      Options = {
        "awslogs-group"         = aws_cloudwatch_log_group.server_log_group.name
        "awslogs-region"        = data.aws_region.current.region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
  depends_on = [aws_instance.vs_code_ec2]
}
resource "aws_cloudwatch_log_group" "server_log_group" {
  name              = "/ecs/${aws_ecs_cluster.ecs_cluster.name}/server"
  retention_in_days = 30
}
resource "aws_ecs_task_definition" "image_generation_task_definition" {
  family                   = "item-images-taskdef"
  cpu                      = 1024
  memory                   = 2048
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }
  container_definitions = jsonencode([{
    Name      = "main"
    Image     = "${aws_ecr_repository.image_generation_repository.repository_url}:latest"
    Essential = true
    PortMappings = [{
      ContainerPort = local.mappings["EcsServiceMapping"]["ImageGeneration"]["ContainerPort"]
      HostPort      = local.mappings["EcsServiceMapping"]["ImageGeneration"]["ContainerPort"]
      Protocol      = "tcp"
    }]
    Environment = [{
      Name  = "PORT"
      Value = local.mappings["EcsServiceMapping"]["ImageGeneration"]["ContainerPort"]
      }, {
      Name  = "ENVIRONMENT"
      Value = var.environment
      }, {
      Name  = "S3_BUCKET_NAME"
      Value = aws_s3_bucket.image_bucket.id
      }, {
      Name  = "CLOUDFRONT_DOMAIN"
      Value = aws_cloudfront_distribution.image_cloud_front_distribution.domain_name
      }, {
      Name  = "REDIS_HOST"
      Value = aws_memorydb_cluster.memory_db_cluster.cluster_endpoint[0].address
    }]
    LogConfiguration = {
      LogDriver = "awslogs"
      Options = {
        "awslogs-group"         = aws_cloudwatch_log_group.image_generation_log_group.name
        "awslogs-region"        = data.aws_region.current.region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
  depends_on = [aws_instance.vs_code_ec2]
}
resource "aws_cloudwatch_log_group" "image_generation_log_group" {
  name              = "/ecs/${aws_ecs_cluster.ecs_cluster.name}/item-images"
  retention_in_days = 30
}
resource "aws_s3_bucket" "client_bucket" {}
resource "aws_cloudfront_origin_access_control" "client_origin_access_control" {
  name                              = "ClientS3BucketOriginAccessControl"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}
resource "aws_cloudfront_distribution" "client_cloud_front_distribution" {
  enabled             = true
  default_root_object = "index.html"
  http_version        = "http3"
  origin {
    domain_name              = aws_s3_bucket.client_bucket.bucket_regional_domain_name
    origin_id                = "S3Origin"
    origin_access_control_id = aws_cloudfront_origin_access_control.client_origin_access_control.id
    s3_origin_config {
      origin_access_identity = ""
    }
  }
  origin {
    domain_name = aws_lb.server_alb.dns_name
    origin_id   = "WebSocketOrigin"
    custom_origin_config {
      http_port                = 80
      origin_keepalive_timeout = 15
      origin_protocol_policy   = "http-only"
      # cfn2tf: 'https_port' is required by aws_cloudfront_distribution but absent from the CloudFormation template; using a provider-compatible default.
      https_port = 443
      # cfn2tf: 'origin_ssl_protocols' is required by aws_cloudfront_distribution but absent from the CloudFormation template; using a provider-compatible default.
      origin_ssl_protocols = ["TLSv1.2"]
    }
  }
  default_cache_behavior {
    target_origin_id       = "S3Origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD", "OPTIONS"]
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
    compress    = true
    min_ttl     = 3600
    default_ttl = 86400
    max_ttl     = 31536000
  }
  ordered_cache_behavior {
    path_pattern           = "/ws*"
    target_origin_id       = "WebSocketOrigin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD", "OPTIONS"]
    forwarded_values {
      query_string = true
      headers      = ["Origin", "Access-Control-Request-Headers", "Access-Control-Request-Method", "Sec-WebSocket-Key", "Sec-WebSocket-Version", "Sec-WebSocket-Protocol", "Sec-WebSocket-Accept", "Sec-WebSocket-Extensions"]
      cookies {
        forward = "none"
      }
    }
    compress = true
  }
  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
  }
  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }
  price_class = "PriceClass_100"
  # cfn2tf: 'restrictions' is required by aws_cloudfront_distribution but absent from the CloudFormation template; using the service default.
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  # cfn2tf: 'viewer_certificate' is required by aws_cloudfront_distribution but absent from the CloudFormation template; using the service default.
  viewer_certificate {
    cloudfront_default_certificate = true
  }
}
resource "aws_s3_bucket_policy" "client_bucket_policy" {
  bucket = aws_s3_bucket.client_bucket.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "cloudfront.amazonaws.com"
      }
      Action   = "s3:GetObject"
      Resource = "arn:aws:s3:::${aws_s3_bucket.client_bucket.id}/*"
      Condition = {
        StringEquals = {
          "AWS:SourceArn" = "arn:aws:cloudfront::${data.aws_caller_identity.current.account_id}:distribution/${aws_cloudfront_distribution.client_cloud_front_distribution.id}"
        }
        Bool = {
          "aws:SecureTransport" = "true"
        }
      }
    }]
  })
}
resource "aws_s3_bucket" "image_bucket" {}
resource "aws_s3_bucket_policy" "image_bucket_policy" {
  bucket = aws_s3_bucket.image_bucket.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "cloudfront.amazonaws.com"
      }
      Action   = "s3:GetObject"
      Resource = "${aws_s3_bucket.image_bucket.arn}/*"
      Condition = {
        StringEquals = {
          "AWS:SourceArn" = "arn:aws:cloudfront::${data.aws_caller_identity.current.account_id}:distribution/${aws_cloudfront_distribution.image_cloud_front_distribution.id}"
        }
        Bool = {
          "aws:SecureTransport" = "true"
        }
      }
    }]
  })
}
resource "aws_cloudfront_origin_access_control" "image_origin_access_control" {
  name                              = "ImageS3BucketOriginAccessControl"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}
resource "aws_cloudfront_distribution" "image_cloud_front_distribution" {
  default_cache_behavior {
    viewer_protocol_policy = "redirect-to-https"
    target_origin_id       = "ItemImageBucketOrigin"
    allowed_methods        = ["GET", "HEAD"]
    forwarded_values {
      query_string = false
      # cfn2tf: 'cookies' is required by aws_cloudfront_distribution but absent from the CloudFormation template; using the service default.
      cookies {
        forward = "none"
      }
    }
    min_ttl     = 3600
    default_ttl = 86400
    max_ttl     = 31536000
    compress    = true
    # cfn2tf: 'cached_methods' is required by aws_cloudfront_distribution but absent from the CloudFormation template; using a provider-compatible default.
    cached_methods = ["GET", "HEAD"]
  }
  enabled      = true
  http_version = "http3"
  origin {
    origin_id                = "ItemImageBucketOrigin"
    domain_name              = aws_s3_bucket.image_bucket.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.image_origin_access_control.id
    s3_origin_config {
      origin_access_identity = ""
    }
  }
  # cfn2tf: 'restrictions' is required by aws_cloudfront_distribution but absent from the CloudFormation template; using the service default.
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  # cfn2tf: 'viewer_certificate' is required by aws_cloudfront_distribution but absent from the CloudFormation template; using the service default.
  viewer_certificate {
    cloudfront_default_certificate = true
  }
}
resource "aws_lb" "server_alb" {
  subnets         = [aws_subnet.public_subneta.id, aws_subnet.public_subnetb.id]
  security_groups = [aws_security_group.server_alb_security_group.id]
  internal        = false
  idle_timeout    = 60
  # TODO cfn2tf: unmapped CloudFormation property 'routing_http_drop_invalid_header_fields_enabled' of AWS::ElasticLoadBalancingV2::LoadBalancer
  # # "true"
}
resource "aws_lb" "image_generation_alb" {
  subnets         = [aws_subnet.private_subneta.id, aws_subnet.private_subnetb.id]
  security_groups = [aws_security_group.image_generation_alb_security_group.id]
  internal        = true
  idle_timeout    = 60
  # TODO cfn2tf: unmapped CloudFormation property 'routing_http_drop_invalid_header_fields_enabled' of AWS::ElasticLoadBalancingV2::LoadBalancer
  # # "true"
}
resource "aws_ecs_cluster" "ecs_cluster" {
  setting {
    name  = "containerInsights"
    value = "enhanced"
  }
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  name       = "${var.stack_name}-ecs-cluster"
  depends_on = [aws_instance.vs_code_ec2]
}
resource "aws_lb_listener" "server_alb_listener" {
  load_balancer_arn = aws_lb.server_alb.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.server_target_group.arn
  }
}
resource "aws_lb_target_group" "server_target_group" {
  port        = local.mappings["EcsServiceMapping"]["Server"]["ContainerPort"]
  protocol    = "HTTP"
  vpc_id      = aws_vpc.vpc.id
  target_type = "ip"
  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
  # TODO cfn2tf: unmapped CloudFormation property '__stickiness_enabled__' of AWS::ElasticLoadBalancingV2::TargetGroup
  # # true
  # TODO cfn2tf: unmapped CloudFormation property 'stickiness_type' of AWS::ElasticLoadBalancingV2::TargetGroup
  # # "lb_cookie"
}
resource "aws_ecs_service" "server_ecs_service" {
  cluster         = aws_ecs_cluster.ecs_cluster.name
  task_definition = aws_ecs_task_definition.server_task_definition.arn
  desired_count   = 2
  launch_type     = "FARGATE"
  network_configuration {
    assign_public_ip = false
    subnets          = [aws_subnet.private_subneta.id, aws_subnet.private_subnetb.id]
    security_groups  = [aws_security_group.server_security_group.id]
  }
  load_balancer {
    container_name   = "main"
    container_port   = local.mappings["EcsServiceMapping"]["Server"]["ContainerPort"]
    target_group_arn = aws_lb_target_group.server_target_group.arn
  }
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  name       = "${var.stack_name}-server-ecs-service"
  depends_on = [aws_lb_listener.server_alb_listener]
}
resource "aws_security_group" "server_security_group" {
  description = "Security group for ecs service"
  vpc_id      = aws_vpc.vpc.id
  ingress {
    protocol        = "tcp"
    from_port       = local.mappings["EcsServiceMapping"]["Server"]["ContainerPort"]
    to_port         = local.mappings["EcsServiceMapping"]["Server"]["ContainerPort"]
    security_groups = [aws_security_group.server_alb_security_group.id]
    description     = "Allow inbound traffic from load balancer to container port"
  }
  egress {
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
  }
  tags = {
    Name = "Server-ecs-service-sg"
  }
}
resource "aws_security_group" "server_alb_security_group" {
  description = "Security group for load balancer"
  vpc_id      = aws_vpc.vpc.id
  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = [aws_vpc.vpc.cidr_block]
    description = "Allow inbound HTTP traffic from Vpc"
  }
  ingress {
    protocol        = "tcp"
    from_port       = 80
    to_port         = 80
    prefix_list_ids = [jsondecode(aws_lambda_invocation.cloud_front_prefix_list.result)["PrefixListId"]]
    description     = "Allow inbound HTTP traffic from CloudFront"
  }
  egress {
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
  }
  tags = {
    Name = "Server-alb-sg"
  }
}
resource "aws_lb_listener" "image_generation_alb_listener" {
  load_balancer_arn = aws_lb.image_generation_alb.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.image_generation_target_group.arn
  }
}
resource "aws_lb_target_group" "image_generation_target_group" {
  port        = local.mappings["EcsServiceMapping"]["ImageGeneration"]["ContainerPort"]
  protocol    = "HTTP"
  vpc_id      = aws_vpc.vpc.id
  target_type = "ip"
  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
  # TODO cfn2tf: unmapped CloudFormation property '__stickiness_enabled__' of AWS::ElasticLoadBalancingV2::TargetGroup
  # # true
  # TODO cfn2tf: unmapped CloudFormation property 'stickiness_type' of AWS::ElasticLoadBalancingV2::TargetGroup
  # # "lb_cookie"
}
resource "aws_ecs_service" "image_generation_ecs_service" {
  cluster         = aws_ecs_cluster.ecs_cluster.name
  task_definition = aws_ecs_task_definition.image_generation_task_definition.arn
  desired_count   = 2
  launch_type     = "FARGATE"
  network_configuration {
    assign_public_ip = false
    subnets          = [aws_subnet.private_subneta.id, aws_subnet.private_subnetb.id]
    security_groups  = [aws_security_group.image_generation_security_group.id]
  }
  load_balancer {
    container_name   = "main"
    container_port   = local.mappings["EcsServiceMapping"]["ImageGeneration"]["ContainerPort"]
    target_group_arn = aws_lb_target_group.image_generation_target_group.arn
  }
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  name       = "${var.stack_name}-image-generation-ecs-service"
  depends_on = [aws_lb_listener.image_generation_alb_listener]
}
resource "aws_security_group" "image_generation_security_group" {
  description = "Security group for ecs service"
  vpc_id      = aws_vpc.vpc.id
  ingress {
    protocol        = "tcp"
    from_port       = local.mappings["EcsServiceMapping"]["ImageGeneration"]["ContainerPort"]
    to_port         = local.mappings["EcsServiceMapping"]["ImageGeneration"]["ContainerPort"]
    security_groups = [aws_security_group.image_generation_alb_security_group.id]
    description     = "Allow inbound traffic from load balancer to container port"
  }
  egress {
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
  }
  tags = {
    Name = "ImageGeneration-ecs-service-sg"
  }
}
resource "aws_security_group" "image_generation_alb_security_group" {
  description = "Security group for load balancer"
  vpc_id      = aws_vpc.vpc.id
  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = [aws_vpc.vpc.cidr_block]
    description = "Allow inbound HTTP traffic from Vpc"
  }
  ingress {
    protocol        = "tcp"
    from_port       = 80
    to_port         = 80
    prefix_list_ids = [jsondecode(aws_lambda_invocation.cloud_front_prefix_list.result)["PrefixListId"]]
    description     = "Allow inbound HTTP traffic from CloudFront"
  }
  egress {
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
  }
  tags = {
    Name = "ImageGeneration-alb-sg"
  }
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
resource "aws_dynamodb_table" "items_table" {
  name         = "Items"
  billing_mode = "PAY_PER_REQUEST"
  point_in_time_recovery {
    enabled = true
  }
  attribute {
    name = "id"
    type = "S"
  }
  hash_key = "id"
}
resource "aws_dynamodb_table" "inventory_table" {
  name         = "Inventory"
  billing_mode = "PAY_PER_REQUEST"
  point_in_time_recovery {
    enabled = true
  }
  attribute {
    name = "id"
    type = "S"
  }
  attribute {
    name = "itemId"
    type = "S"
  }
  hash_key  = "id"
  range_key = "itemId"
}
resource "aws_dynamodb_table" "location_table" {
  name         = "Location"
  billing_mode = "PAY_PER_REQUEST"
  point_in_time_recovery {
    enabled = true
  }
  attribute {
    name = "itemId"
    type = "S"
  }
  attribute {
    name = "location"
    type = "S"
  }
  hash_key  = "itemId"
  range_key = "location"
}
resource "aws_dynamodb_table" "users_table" {
  name         = "Users"
  billing_mode = "PAY_PER_REQUEST"
  point_in_time_recovery {
    enabled = true
  }
  attribute {
    name = "userId"
    type = "S"
  }
  hash_key = "userId"
}
resource "aws_dynamodb_table" "usernames_table" {
  name         = "Usernames"
  billing_mode = "PAY_PER_REQUEST"
  point_in_time_recovery {
    enabled = true
  }
  attribute {
    name = "username"
    type = "S"
  }
  hash_key = "username"
}
resource "aws_dynamodb_table" "persona_table" {
  name         = "Persona"
  billing_mode = "PAY_PER_REQUEST"
  point_in_time_recovery {
    enabled = true
  }
  attribute {
    name = "userId"
    type = "S"
  }
  attribute {
    name = "detail"
    type = "S"
  }
  hash_key  = "userId"
  range_key = "detail"
}
resource "aws_memorydb_cluster" "memory_db_cluster" {
  name                     = "memorydb"
  node_type                = "db.r6g.large"
  engine_version           = 7.1
  num_shards               = 1
  num_replicas_per_shard   = 0
  subnet_group_name        = aws_memorydb_subnet_group.memory_db_subnet_group.id
  parameter_group_name     = "default.memorydb-redis7.search"
  security_group_ids       = [aws_security_group.memory_db_security_group.id]
  acl_name                 = "open-access"
  tls_enabled              = false
  maintenance_window       = "sun:05:00-sun:06:00"
  snapshot_retention_limit = 7
}
resource "aws_memorydb_subnet_group" "memory_db_subnet_group" {
  description = "Subnet group for MemoryDB cluster"
  subnet_ids  = [aws_subnet.private_subneta.id, aws_subnet.private_subnetb.id]
  name        = "memorydb-subnet-group"
}
resource "aws_security_group" "memory_db_security_group" {
  description = "Security group for MemoryDB cluster"
  vpc_id      = aws_vpc.vpc.id
  ingress {
    protocol        = "tcp"
    from_port       = 6379
    to_port         = 6379
    security_groups = [aws_security_group.image_generation_security_group.id]
    description     = "Allow traffic from Fargate service to MemoryDB"
  }
  ingress {
    protocol    = "tcp"
    from_port   = 6379
    to_port     = 6379
    cidr_blocks = [aws_vpc.vpc.cidr_block]
    description = "Allow inbound Redis traffic from VPC CIDR"
  }
  tags = {
    Name = "memorydb-sg"
  }
}
resource "aws_lambda_invocation" "cloud_front_prefix_list" {
  function_name = aws_lambda_function.custom_lambda_function.arn
  input = jsonencode({
    PrefixListName = "com.amazonaws.global.cloudfront.origin-facing"
  })
}
resource "aws_lambda_function" "custom_lambda_function" {
  runtime          = "python3.13"
  handler          = "index.lambda_handler"
  role             = aws_iam_role.custom_lambda_iam_role.arn
  timeout          = 30
  filename         = data.archive_file.custom_lambda_function.output_path
  source_code_hash = data.archive_file.custom_lambda_function.output_base64sha256
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  function_name = "${var.stack_name}-custom-lambda-function"
}
resource "aws_iam_role" "custom_lambda_iam_role" {
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
# CloudFormation output: VsCode
output "vs_code" {
  value       = "http://${aws_instance.vs_code_ec2.public_ip}:8000"
  description = "Public IP Address of the VS Code Server EC2 instance"
}
# CloudFormation output: GameClient
output "game_client" {
  value       = "https://${aws_cloudfront_distribution.client_cloud_front_distribution.domain_name}"
  description = "Domain Name of the Game Client CloudFront Distribution"
}
