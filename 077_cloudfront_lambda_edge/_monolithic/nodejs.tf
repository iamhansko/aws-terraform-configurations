# Generated from 077_cloudfront_lambda_edge/nodejs.yaml by tools/cfn2tf.
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
  default     = "nodejs"
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
  stack_id                                  = "arn:${data.aws_partition.current.partition}:cloudformation:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:stack/${var.stack_name}/${random_uuid.stack_id.result}"
  cond_security_group_inbound_from_anywhere = (var.inbound_from_anywhere == "True")
}
# --- Resources split out of composite CloudFormation resources ---
data "archive_file" "ec2_origin_lambda_function" {
  type        = "zip"
  source_file = "${path.module}/lambda_src/ec2_origin_lambda_function/index.js"
  output_path = "${path.module}/build/ec2_origin_lambda_function.zip"
}
data "archive_file" "s3_origin_lambda_function" {
  type        = "zip"
  source_file = "${path.module}/lambda_src/s3_origin_lambda_function/index.js"
  output_path = "${path.module}/build/s3_origin_lambda_function.zip"
}
resource "aws_iam_role_policy_attachment" "lambda_function_role" {
  role       = aws_iam_role.lambda_function_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
resource "aws_s3_bucket_public_access_block" "s3_bucket_pab" {
  bucket                  = aws_s3_bucket.s3_bucket.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
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
resource "aws_iam_role_policy_attachment" "vs_code_ec2_iam_role" {
  role       = aws_iam_role.vs_code_ec2_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
# --- Resources ---
resource "aws_lambda_function" "ec2_origin_lambda_function" {
  runtime          = "nodejs22.x"
  handler          = "index.handler"
  role             = aws_iam_role.lambda_function_role.arn
  publish          = true
  filename         = data.archive_file.ec2_origin_lambda_function.output_path
  source_code_hash = data.archive_file.ec2_origin_lambda_function.output_base64sha256
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  function_name = "${var.stack_name}-ec2-origin-lambda-function"
}
resource "aws_lambda_function" "s3_origin_lambda_function" {
  runtime          = "nodejs22.x"
  handler          = "index.handler"
  role             = aws_iam_role.lambda_function_role.arn
  publish          = true
  filename         = data.archive_file.s3_origin_lambda_function.output_path
  source_code_hash = data.archive_file.s3_origin_lambda_function.output_base64sha256
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  function_name = "${var.stack_name}-s3-origin-lambda-function"
}
# === S3OriginLambdaVersion (AWS::Lambda::Version) NOT CONVERTED ===
# Terraform publishes versions via `publish = true` on aws_lambda_function.
# Original CloudFormation definition:
# # {
# #   "Type": "AWS::Lambda::Version",
# #   "Properties": {
# #     "FunctionName": {
# #       "Ref": "S3OriginLambdaFunction"
# #     }
# #   }
# # }
# === Ec2OriginLambdaVersion (AWS::Lambda::Version) NOT CONVERTED ===
# Terraform publishes versions via `publish = true` on aws_lambda_function.
# Original CloudFormation definition:
# # {
# #   "Type": "AWS::Lambda::Version",
# #   "Properties": {
# #     "FunctionName": {
# #       "Ref": "Ec2OriginLambdaFunction"
# #     }
# #   }
# # }
resource "aws_iam_role" "lambda_function_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["lambda.amazonaws.com", "edgelambda.amazonaws.com"]
      }
      Action = "sts:AssumeRole"
    }]
  })
}
resource "aws_s3_bucket" "s3_bucket" {}
resource "aws_s3_bucket_policy" "s3_bucket_policy" {
  bucket = aws_s3_bucket.s3_bucket.id
  policy = jsonencode({
    Statement = [{
      Effect    = "Allow"
      Principal = "*"
      Action    = ["s3:GetObject"]
      Resource  = "${aws_s3_bucket.s3_bucket.arn}/*"
    }]
  })
}
resource "aws_cloudfront_distribution" "cloud_front_distribution" {
  enabled             = true
  default_root_object = "index.html"
  default_cache_behavior {
    target_origin_id       = "S3Origin"
    viewer_protocol_policy = "redirect-to-https"
    cache_policy_id        = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    lambda_function_association {
      event_type = "viewer-request"
      lambda_arn = aws_lambda_function.s3_origin_lambda_function.qualified_arn
    }
    # cfn2tf: 'allowed_methods' is required by aws_cloudfront_distribution but absent from the CloudFormation template; using a provider-compatible default.
    allowed_methods = ["GET", "HEAD"]
    # cfn2tf: 'cached_methods' is required by aws_cloudfront_distribution but absent from the CloudFormation template; using a provider-compatible default.
    cached_methods = ["GET", "HEAD"]
  }
  ordered_cache_behavior {
    path_pattern             = "/code"
    target_origin_id         = "Ec2Origin"
    compress                 = true
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cache_policy_id          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    origin_request_policy_id = "216adef6-5c7f-47e4-b989-5492eafa07d3"
    lambda_function_association {
      event_type = "viewer-request"
      lambda_arn = aws_lambda_function.ec2_origin_lambda_function.qualified_arn
    }
    # cfn2tf: 'cached_methods' is required by aws_cloudfront_distribution but absent from the CloudFormation template; using a provider-compatible default.
    cached_methods = ["GET", "HEAD"]
  }
  ordered_cache_behavior {
    path_pattern             = "/code/*"
    target_origin_id         = "Ec2Origin"
    compress                 = true
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cache_policy_id          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    origin_request_policy_id = "216adef6-5c7f-47e4-b989-5492eafa07d3"
    lambda_function_association {
      event_type = "viewer-request"
      lambda_arn = aws_lambda_function.ec2_origin_lambda_function.qualified_arn
    }
    # cfn2tf: 'cached_methods' is required by aws_cloudfront_distribution but absent from the CloudFormation template; using a provider-compatible default.
    cached_methods = ["GET", "HEAD"]
  }
  origin {
    origin_id   = "S3Origin"
    domain_name = aws_s3_bucket.s3_bucket.bucket_regional_domain_name
    s3_origin_config {
      origin_access_identity = ""
    }
  }
  origin {
    origin_id   = "Ec2Origin"
    domain_name = aws_instance.vs_code_ec2.public_dns
    custom_origin_config {
      http_port              = 80
      origin_protocol_policy = "http-only"
      # cfn2tf: 'https_port' is required by aws_cloudfront_distribution but absent from the CloudFormation template; using a provider-compatible default.
      https_port = 443
      # cfn2tf: 'origin_ssl_protocols' is required by aws_cloudfront_distribution but absent from the CloudFormation template; using a provider-compatible default.
      origin_ssl_protocols = ["TLSv1.2"]
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
resource "aws_subnet" "public_subnet" {
  availability_zone       = "${data.aws_region.current.region}a"
  cidr_block              = "10.0.0.0/24"
  map_public_ip_on_launch = true
  tags = {
    Name = "public-subnet"
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_route_table_association" "public_subnet_route_table_association" {
  route_table_id = aws_route_table.public_subnet_route_table.id
  subnet_id      = aws_subnet.public_subnet.id
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
resource "aws_key_pair" "key_pair" {
  key_name   = "key-${element(split("-", element(split("/", local.stack_id), 2)), 3)}"
  public_key = tls_private_key.key_pair.public_key_openssh
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

export VSC_VERSION="4.104.2"
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

dnf install -yq nginx
echo 'server {
  location = /code {
    return 302 /code/$is_args$args;
  }
  location /code/ {
    proxy_pass http://localhost:8000/;
    proxy_set_header Host $http_host;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection upgrade;
    proxy_set_header Accept-Encoding gzip;
  }
}' > /etc/nginx/conf.d/code-server.conf
systemctl restart nginx

dnf install -yq docker
systemctl enable --now docker
# usermod -aG docker ec2-user
# newgrp docker
chmod 666 /var/run/docker.sock

cd /home/ec2-user
echo "<h2>Hello World</h2>" > index.html
aws s3 cp index.html s3://${aws_s3_bucket.s3_bucket.id}

/opt/aws/bin/cfn-signal -e $? --stack ${var.stack_name} --resource VsCodeEc2 --region ${data.aws_region.current.region}
EOT
  subnet_id                   = aws_subnet.public_subnet.id
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
      from_port   = 80
      to_port     = 80
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
# --- Outputs ---
# CloudFormation output: DistributionDomainName
output "distribution_domain_name" {
  value       = "https://${aws_cloudfront_distribution.cloud_front_distribution.domain_name}/code"
  description = "CloudFront Distribution Domain Name"
}
