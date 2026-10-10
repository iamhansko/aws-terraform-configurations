# Generated from 063_gamelift_flexmatch/template.yaml by tools/cfn2tf.
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
  default     = "template"
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
resource "aws_iam_role_policy_attachment" "vs_code_ec2_iam_role" {
  role       = aws_iam_role.vs_code_ec2_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
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
dnf install -yq git
dnf groupinstall -yq "Development Tools"

export VSC_VERSION="4.102.3"
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

sudo -Eu ec2-user bash << 'EOF'
cd /home/ec2-user
git clone https://github.com/iamhansko/aws-gamelift-sample.git
mv aws-gamelift-sample gomoku

# cd /home/ec2-user/gomoku/Lambda
# rm code.zip
# sed -i 's/us-east-1/${data.aws_region.current.region}/g' *.py
# zip code.zip *.py redis redis-6.4.0.dist-info

echo '[config]

# GameResult SQS
SQS_REGION = ${data.aws_region.current.region}
SQS_ENDPOINT = ${aws_sqs_queue.game_result_queue.url}
ROLE_ARN = ${aws_iam_role.gomoku_game_lift_fleet_role.arn}' > ./gomoku/bin/FlexMatch/GomokuServer/Binaries/Win64/config.ini
cd ./gomoku/bin/FlexMatch/GomokuServer
zip -r server.zip ./*
mv server.zip /home/ec2-user/

aws s3 cp --recursive /home/ec2-user/gomoku/ s3://${aws_s3_bucket.game_source_s3_bucket.id}
aws s3 cp /home/ec2-user/server.zip s3://${aws_s3_bucket.game_source_s3_bucket.id}
EOF

/opt/aws/bin/cfn-signal -e $? --stack ${var.stack_name} --resource VsCodeEc2 --region ${data.aws_region.current.region}
EOT
  subnet_id                   = aws_subnet.public_subneta.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.vs_code_ec2_security_group.id]
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
resource "aws_ssm_association" "ssm_association" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = 600
  targets {
    key    = "InstanceIds"
    values = [aws_instance.vs_code_ec2.id]
  }
  parameters = {
    commands = join("\n", ["su - ec2-user << 'SSMEOF'\nexport HOME=/home/ec2-user && cd $HOME\nsed -i 's/niop6gw2v0/${aws_api_gateway_rest_api.gomoku_api.id}/g' ./gomoku/web/main.js\nsed -i 's/us-east-1/${data.aws_region.current.region}/g' ./gomoku/web/main.js\naws s3 cp --recursive ./gomoku/web/ s3://${aws_s3_bucket.web_s3_bucket.id}\n\ncd ./gomoku/bin/FlexMatch\necho '[config]\nMATCH_SERVER_API = https://${aws_api_gateway_rest_api.gomoku_api.id}.execute-api.${data.aws_region.current.region}.amazonaws.com/prod\nPLAYER_NAME = Amazonian\nPLAYER_PASSWD = simplepw00' > Client_player1/config.ini\necho '[config]\nMATCH_SERVER_API = https://${aws_api_gateway_rest_api.gomoku_api.id}.execute-api.${data.aws_region.current.region}.amazonaws.com/prod\nPLAYER_NAME = Ahro\nPLAYER_PASSWD = simplepw00' > Client_player2/config.ini\nzip -r /home/ec2-user/client.zip Client_player1/ Client_player2/\naws s3 cp /home/ec2-user/client.zip s3://${aws_s3_bucket.game_source_s3_bucket.id}\nSSMEOF\n"])
  }
  depends_on = [aws_instance.vs_code_ec2, aws_api_gateway_deployment.gomoku_api_deployment]
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
  subnet_ids  = [aws_subnet.public_subneta.id, aws_subnet.public_subnetb.id, aws_subnet.private_subneta.id, aws_subnet.private_subnetb.id]
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
  depends_on    = [aws_instance.vs_code_ec2]
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
    subnet_ids         = [aws_subnet.public_subneta.id, aws_subnet.public_subnetb.id, aws_subnet.private_subneta.id, aws_subnet.private_subnetb.id]
  }
  s3_bucket  = aws_s3_bucket.game_source_s3_bucket.id
  s3_key     = "Lambda/code.zip"
  depends_on = [aws_instance.vs_code_ec2]
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
    subnet_ids         = [aws_subnet.public_subneta.id, aws_subnet.public_subnetb.id, aws_subnet.private_subneta.id, aws_subnet.private_subnetb.id]
  }
  s3_bucket  = aws_s3_bucket.game_source_s3_bucket.id
  s3_key     = "Lambda/code.zip"
  depends_on = [aws_instance.vs_code_ec2]
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
  depends_on    = [aws_instance.vs_code_ec2]
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
  depends_on    = [aws_instance.vs_code_ec2]
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
  depends_on    = [aws_instance.vs_code_ec2]
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
    Version = "2008-10-17"
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
  depends_on = [aws_instance.vs_code_ec2]
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
# --- Outputs ---
# CloudFormation output: VsCode
output "vs_code" {
  value       = "http://${aws_instance.vs_code_ec2.public_ip}:8000"
  description = "Public IP Address of the VS Code"
}
# CloudFormation output: GomokuWeb
output "gomoku_web" {
  value       = aws_s3_bucket.web_s3_bucket.website_endpoint
  description = "Gomoku Leaderboard URL"
}
# CloudFormation output: ClientZipFileDownload
output "client_zip_file_download" {
  value = "https://${data.aws_region.current.region}.console.aws.amazon.com/s3/object/${aws_s3_bucket.game_source_s3_bucket.id}?region=${data.aws_region.current.region}&bucketType=general&prefix=client.zip"
}
