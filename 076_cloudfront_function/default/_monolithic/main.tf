# Generated from 076_cloudfront_function/default.yaml by tools/cfn2tf.
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
  default     = "default"
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
  stack_id = "arn:${data.aws_partition.current.partition}:cloudformation:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:stack/${var.stack_name}/${random_uuid.stack_id.result}"
  # One group of the generated stack id. aws_key_pair below already built its name this way, inline; it is a
  # local now because the CloudFront function names need the same thing and the expression should exist once.
  #
  # Hand edit, not conversion output: the CloudFormation template named its functions literally, so two stacks
  # from it collided in CloudFormation too - CloudFront function names are unique per account, not per region.
  # This project is two variants that are meant to be independently applicable, and they are byte-identical
  # apart from the key value stores, so without this the second one applied into an account fails.
  stack_suffix                              = element(split("-", element(split("/", local.stack_id), 2)), 3)
  cond_security_group_inbound_from_anywhere = (var.inbound_from_anywhere == "True")
}
# --- Resources split out of composite CloudFormation resources ---
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
    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.s3_origin_cloud_front_function.id
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
    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.ec2_origin_cloud_front_function.id
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
    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.ec2_origin_cloud_front_function.id
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
resource "aws_cloudfront_function" "s3_origin_cloud_front_function" {
  # Suffixed: the name is unique per account and nothing references the function by it - the distribution
  # above takes the resource's id (see local.stack_suffix).
  name    = "S3OriginFunction-${local.stack_suffix}"
  publish = true
  code    = "function handler(event) {\n    var response = {\n        statusCode: 302,\n        statusDescription: 'Found',\n        headers: {\n            'cloudfront-functions': { value: 'generated-by-CloudFront-Functions' },\n            'location': { value: 'https://aws.amazon.com/cloudfront/' }\n        }\n    };\n    return response;\n}\n"
  runtime = "cloudfront-js-2.0"
  comment = "S3 Origin"
}
resource "aws_cloudfront_function" "ec2_origin_cloud_front_function" {
  name    = "Ec2OriginFunction-${local.stack_suffix}"
  publish = true
  code    = "function handler(event) {\n    var response = {\n        statusCode: 302,\n        statusDescription: 'Found',\n        headers: {\n            'cloudfront-functions': { value: 'generated-by-CloudFront-Functions' },\n            'location': { value: 'https://aws.amazon.com/cloudfront/' }\n        }\n    };\n    return response;\n}\n"
  runtime = "cloudfront-js-2.0"
  comment = "EC2 Origin"
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
  # The same suffix the CloudFront function names take, through the local rather than inline, so the two
  # cannot drift apart. The resulting name is unchanged.
  key_name   = "key-${local.stack_suffix}"
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
echo "server {
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
}" > /etc/nginx/conf.d/code-server.conf
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
  # Hand edit, not conversion output. CloudFormation's AWS::IAM::InstanceProfile takes a Roles list, so the
  # conversion wrote jsonencode([...]) here - but this attribute is a single role name, an instance profile
  # holds at most one role, and a JSON array string is not a role name. validate and plan both pass; the
  # apply fails in IAM (rules.md A-3).
  role = aws_iam_role.vs_code_ec2_iam_role.name
}
# --- Outputs ---
# CloudFormation output: DistributionDomainName
output "distribution_domain_name" {
  value       = "https://${aws_cloudfront_distribution.cloud_front_distribution.domain_name}/code"
  description = "CloudFront Distribution Domain Name"
}
