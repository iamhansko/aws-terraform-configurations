# Generated from 093_ai_streamable_http_lambda_mcp_server/q_cli.yaml by tools/cfn2tf.
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
  default     = "q-cli"
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
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
  description = "(SSM parameter path; resolved by the aws_ssm_parameter data source)"
}
data "aws_ssm_parameter" "ami_id" {
  name = var.ami_id
}
variable "mcp_auth_token" {
  type    = string
  default = "Peccy"
}
# --- Mappings / Conditions ---
locals {
  mappings = {
    ResourceMap = {
      Vpc = {
        Name      = "vpc"
        CidrBlock = "10.1.0.0/16"
      }
      PublicSubnet = {
        Name = "public"
      }
      InternetGateway = {
        Name = "igw"
      }
      BastionEc2 = {
        Name         = "bastion"
        InstanceType = "t3.medium"
      }
    }
    AWSRegions2PrefixListID = {
      "ap-northeast-1" = {
        PrefixList = "pl-58a04531"
      }
      "ap-northeast-2" = {
        PrefixList = "pl-22a6434b"
      }
      "ap-northeast-3" = {
        PrefixList = "pl-31a14458"
      }
      "ap-south-1" = {
        PrefixList = "pl-9aa247f3"
      }
      "ap-southeast-1" = {
        PrefixList = "pl-31a34658"
      }
      "ap-southeast-2" = {
        PrefixList = "pl-b8a742d1"
      }
      "ca-central-1" = {
        PrefixList = "pl-38a64351"
      }
      "eu-central-1" = {
        PrefixList = "pl-a3a144ca"
      }
      "eu-north-1" = {
        PrefixList = "pl-fab65393"
      }
      "eu-west-1" = {
        PrefixList = "pl-4fa04526"
      }
      "eu-west-2" = {
        PrefixList = "pl-93a247fa"
      }
      "eu-west-3" = {
        PrefixList = "pl-75b1541c"
      }
      "sa-east-1" = {
        PrefixList = "pl-5da64334"
      }
      "us-east-1" = {
        PrefixList = "pl-3b927c52"
      }
      "us-east-2" = {
        PrefixList = "pl-b6a144df"
      }
      "us-west-1" = {
        PrefixList = "pl-4ea04527"
      }
      "us-west-2" = {
        PrefixList = "pl-82a045eb"
      }
    }
  }
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
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}
data "archive_file" "mcp_authorizer_function" {
  type        = "zip"
  source_file = "${path.module}/lambda_src/mcp_authorizer_function/index.py"
  output_path = "${path.module}/build/mcp_authorizer_function.zip"
}
# AWS SAM creates an execution role implicitly; Terraform requires one, so the equivalent role is declared here.
resource "aws_iam_role" "mcp_authorizer_function_role" {
  name = "${var.stack_name}-mcp-authorizer-function-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}
resource "aws_iam_role_policy_attachment" "mcp_authorizer_function_role_basic" {
  role       = aws_iam_role.mcp_authorizer_function_role.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
data "archive_file" "mcp_server_function" {
  type        = "zip"
  source_file = "${path.module}/lambda_src/mcp_server_function/index.py"
  output_path = "${path.module}/build/mcp_server_function.zip"
}
# AWS SAM creates an execution role implicitly; Terraform requires one, so the equivalent role is declared here.
resource "aws_iam_role" "mcp_server_function_role" {
  name = "${var.stack_name}-mcp-server-function-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}
resource "aws_iam_role_policy_attachment" "mcp_server_function_role_basic" {
  role       = aws_iam_role.mcp_server_function_role.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
# --- Resources ---
resource "aws_key_pair" "key_pair" {
  key_name   = "key-${local.stack_suffix}"
  public_key = tls_private_key.key_pair.public_key_openssh
}
resource "aws_vpc" "vpc" {
  cidr_block           = local.mappings["ResourceMap"]["Vpc"]["CidrBlock"]
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = local.mappings["ResourceMap"]["Vpc"]["Name"]
  }
}
resource "aws_subnet" "public_subnet_a" {
  availability_zone = "${data.aws_region.current.region}a"
  cidr_block        = element([for __i in range(4) : cidrsubnet(aws_vpc.vpc.cidr_block, 32 - 8 - tonumber(split("/", aws_vpc.vpc.cidr_block)[1]), __i)], 0)
  tags = {
    Name = join("-", [local.mappings["ResourceMap"]["PublicSubnet"]["Name"], "a"])
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
resource "aws_route" "public_subnet_route" {
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.internet_gateway.id
  route_table_id         = aws_route_table.public_subnet_route_table.id
}
# CreationPolicy: CloudFormation CreationPolicy (cfn-signal) has no Terraform equivalent; the wait is not reproduced.
# # {
# #   "ResourceSignal": {
# #     "Count": "1",
# #     "Timeout": "PT7M"
# #   }
# # }
resource "aws_instance" "bastion_ec2" {
  ami           = data.aws_ssm_parameter.ami_id.insecure_value
  instance_type = local.mappings["ResourceMap"]["BastionEc2"]["InstanceType"]
  key_name      = aws_key_pair.key_pair.key_name
  tags = {
    Name = local.mappings["ResourceMap"]["BastionEc2"]["Name"]
  }
  iam_instance_profile        = aws_iam_instance_profile.bastion_ec2_instance_profile.name
  user_data                   = <<EOT
#!/bin/bash
dnf update -yq
dnf groupinstall -yq "Development Tools"
dnf install -yq git
dnf install -yq docker
systemctl enable --now docker
# usermod -aG docker ec2-user
# newgrp docker
chmod 666 /var/run/docker.sock

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
    description     = "com.amazonaws.global.cloudfront.origin-facing"
    protocol        = "tcp"
    from_port       = 8000
    to_port         = 8000
    prefix_list_ids = [local.mappings["AWSRegions2PrefixListID"][data.aws_region.current.region]["PrefixList"]]
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
  name = "Ec2PowerUserRole-${local.stack_suffix}"
}
resource "aws_iam_instance_profile" "bastion_ec2_instance_profile" {
  name = "Ec2PowerUserProfile-${local.stack_suffix}"
  # An instance profile holds at most one role, so this attribute is a single
  # role name string - not the list CloudFormation's AWS::IAM::InstanceProfile
  # Roles property takes. jsonencode([...]) here sends the literal string
  # ["terraform-..."] as roleName, which IAM rejects with a ValidationError
  # during apply, while terraform validate and plan both pass because the
  # attribute is a string either way (rules.md A-3).
  role = aws_iam_role.bastion_ec2_iam_role.name
}
resource "aws_cloudfront_distribution" "cloud_front_distribution" {
  origin {
    domain_name = aws_instance.bastion_ec2.public_dns
    origin_id   = aws_instance.bastion_ec2.public_dns
    custom_origin_config {
      http_port              = 8000
      origin_protocol_policy = "http-only"
      # cfn2tf: 'https_port' is required by aws_cloudfront_distribution but absent from the CloudFormation template; using a provider-compatible default.
      https_port = 443
      # cfn2tf: 'origin_ssl_protocols' is required by aws_cloudfront_distribution but absent from the CloudFormation template; using a provider-compatible default.
      origin_ssl_protocols = ["TLSv1.2"]
    }
  }
  enabled = true
  default_cache_behavior {
    allowed_methods = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    forwarded_values {
      query_string = false
      # cfn2tf: 'cookies' is required by aws_cloudfront_distribution but absent from the CloudFormation template; using the service default.
      cookies {
        forward = "none"
      }
    }
    compress                 = false
    target_origin_id         = aws_instance.bastion_ec2.public_dns
    viewer_protocol_policy   = "allow-all"
    cache_policy_id          = aws_cloudfront_cache_policy.cloud_front_cache_policy.id
    origin_request_policy_id = "216adef6-5c7f-47e4-b989-5492eafa07d3"
    # cfn2tf: 'cached_methods' is required by aws_cloudfront_distribution but absent from the CloudFormation template; using a provider-compatible default.
    cached_methods = ["GET", "HEAD"]
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
resource "aws_cloudfront_cache_policy" "cloud_front_cache_policy" {
  default_ttl = 86400
  max_ttl     = 31536000
  min_ttl     = 1
  name        = join("-", ["VSCode", element(split("-", element(split("/", local.stack_id), 2)), 4)])
  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      cookie_behavior = "all"
    }
    enable_accept_encoding_gzip = false
    headers_config {
      header_behavior = "whitelist"
      headers {
        items = ["Accept-Charset", "Authorization", "Origin", "Accept", "Referer", "Host", "Accept-Language", "Accept-Encoding", "Accept-Datetime"]
      }
    }
    query_strings_config {
      query_string_behavior = "all"
    }
  }
}
resource "aws_api_gateway_rest_api" "mcp_api" {
  # TODO cfn2tf: unmapped CloudFormation property 'StageName' of AWS::Serverless::Api
  # # "Prod"
  # TODO cfn2tf: unmapped CloudFormation property 'Auth' of AWS::Serverless::Api
  # # {
  # #   "Authorizers": {
  # #     "TokenAuthorizer": {
  # #       "FunctionArn": {
  # #         "Fn::GetAtt": [
  # #           "McpAuthorizerFunction",
  # #           "Arn"
  # #         ]
  # #       },
  # #       "FunctionPayloadType": "TOKEN",
  # #       "Identity": {
  # #         "ReauthorizeEvery": 300,
  # #         "Header": "Authorization"
  # #       }
  # #     }
  # #   }
  # # }
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  name = "${var.stack_name}-mcp-api"
}
resource "aws_lambda_function" "mcp_authorizer_function" {
  handler = "index.lambda_handler"
  runtime = "python3.13"
  timeout = 60
  environment {
    variables = {
      MCP_AUTH_TOKEN = var.mcp_auth_token
    }
  }
  filename         = data.archive_file.mcp_authorizer_function.output_path
  source_code_hash = data.archive_file.mcp_authorizer_function.output_base64sha256
  role             = aws_iam_role.mcp_authorizer_function_role.arn
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  function_name = "${var.stack_name}-mcp-authorizer-function"
}
resource "aws_dynamodb_table" "mcp_sessions_table" {
  name = "${var.stack_name}-mcp-sessions"
  attribute {
    name = "session_id"
    type = "S"
  }
  billing_mode = "PAY_PER_REQUEST"
  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }
  tags = {
    Purpose = "MCP Session Management"
  }
  hash_key = "session_id"
}
resource "aws_lambda_function" "mcp_server_function" {
  handler = "index.lambda_handler"
  runtime = "python3.13"
  timeout = 60
  environment {
    variables = {
      MCP_SESSION_TABLE = aws_dynamodb_table.mcp_sessions_table.name
    }
  }
  layers           = [aws_lambda_layer_version.lambda_layer.arn]
  filename         = data.archive_file.mcp_server_function.output_path
  source_code_hash = data.archive_file.mcp_server_function.output_base64sha256
  role             = aws_iam_role.mcp_server_function_role.arn
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  function_name = "${var.stack_name}-mcp-server-function"
}
resource "aws_s3_bucket" "lambda_layer_source_bucket" {}
resource "aws_ssm_association" "lambda_layer_ssm_association" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = 180
  targets {
    key    = "InstanceIds"
    values = [aws_instance.bastion_ec2.id]
  }
  parameters = {
    commands = join("\n", ["dnf install -yq python3.13\nln -sf /usr/bin/python3.13 /usr/bin/python\npython -m ensurepip --upgrade\nwget -qO- https://astral.sh/uv/install.sh | sh\nsu - ec2-user << 'EOF'\ncd /home/ec2-user\nmkdir -p ./layer/python\npython -m pip install --platform=manylinux2014_x86_64 --only-binary=:all: awslabs.mcp_lambda_handler -t ./layer/python\ncd /home/ec2-user/layer\nzip -r layer.zip ./python/\naws s3 cp layer.zip s3://${aws_s3_bucket.lambda_layer_source_bucket.id}\nrm layer.zip\nEOF\n"])
  }
}
resource "aws_lambda_layer_version" "lambda_layer" {
  compatible_architectures = ["x86_64", "arm64"]
  compatible_runtimes      = ["python3.13", "python3.12", "python3.11"]
  s3_bucket                = aws_s3_bucket.lambda_layer_source_bucket.id
  s3_key                   = "layer.zip"
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  layer_name = "${var.stack_name}-lambda-layer"
  depends_on = [aws_ssm_association.lambda_layer_ssm_association]
}
resource "aws_ssm_association" "q_developer_ssm_association" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = 180
  targets {
    key    = "InstanceIds"
    values = [aws_instance.bastion_ec2.id]
  }
  parameters = {
    commands = join("\n", ["su - ec2-user <<'EOF'\nexport HOME=/home/ec2-user/\ncd $HOME\n# code-server --install-extension amazonwebservices.amazon-q-vscode\nwget -qO- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash\nexport NVM_DIR=\"$([ -z \"$${XDG_CONFIG_HOME-}\" ] && printf %s \"$${HOME}/.nvm\" || printf %s \"$${XDG_CONFIG_HOME}/nvm\")\"\n[ -s \"$NVM_DIR/nvm.sh\" ] && \\. \"$NVM_DIR/nvm.sh\"\nnvm install --lts\ncurl -s --proto '=https' --tlsv1.2 -sSf \"https://desktop-release.q.us-east-1.amazonaws.com/latest/q-x86_64-linux.zip\" -o \"q.zip\"\nunzip q.zip\n./q/install.sh --no-confirm\nmkdir -p /home/ec2-user/.aws/amazonq\necho '{\n  \"mcpServers\": {\n    \"awslabs.aws-documentation-mcp-server\": {\n      \"command\": \"uvx\",\n      \"args\": [\"awslabs.aws-documentation-mcp-server@latest\"],\n      \"env\": {\n        \"FASTMCP_LOG_LEVEL\": \"ERROR\",\n        \"AWS_DOCUMENTATION_PARTITION\": \"aws\"\n      },\n      \"disabled\": false,\n      \"autoApprove\": []\n    },\n    \"streamable-http-mcp-server\": {\n      \"command\": \"npx\",\n      \"args\": [\n        \"mcp-remote\",\n        \"https://${aws_api_gateway_rest_api.mcp_api.id}.execute-api.${data.aws_region.current.region}.amazonaws.com/Prod/mcp\",\n        \"--header\",\n        \"Authorization: Bearer ${var.mcp_auth_token}\"\n      ]\n    }\n  }\n}' > /home/ec2-user/.aws/amazonq/mcp.json\nEOF\n"])
  }
}
# --- Outputs ---
# CloudFormation output: MCPServerApi
output "mcp_server_api" {
  value       = "https://${aws_api_gateway_rest_api.mcp_api.id}.execute-api.${data.aws_region.current.region}.amazonaws.com/Prod/mcp"
  description = "API Gateway endpoint URL for MCP server"
}
# CloudFormation output: McpSessionsTableName
output "mcp_sessions_table_name" {
  value       = aws_dynamodb_table.mcp_sessions_table.name
  description = "Name of the DynamoDB table for MCP sessions"
}
# CloudFormation output: McpRequestHeader
output "mcp_request_header" {
  value = "Authorization : Bearer ${var.mcp_auth_token}"
}
# CloudFormation output: VsCode
output "vs_code" {
  value = "https://${aws_cloudfront_distribution.cloud_front_distribution.domain_name}"
}
