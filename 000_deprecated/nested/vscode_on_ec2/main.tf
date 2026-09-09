# Generated from 000_deprecated/nested/vscode_on_ec2.yaml by tools/cfn2tf.
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
  default     = "vscode-on-ec2"
  description = "Stands in for AWS::StackName."
}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}
# Provides the unique suffix that AWS::StackId supplies in CloudFormation.
resource "random_uuid" "stack_id" {}
# --- Parameters ---
variable "vpc_id" {
  type        = string
  description = "Existing VPC ID"
}
variable "public_subnet_id" {
  type        = string
  description = "Existing Public Subnet ID"
}
variable "ami_id" {
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
  description = "EC2 AMI Id(SSM parameter path; resolved by the aws_ssm_parameter data source)"
}
data "aws_ssm_parameter" "ami_id" {
  name = var.ami_id
}
variable "instance_type" {
  type        = string
  default     = "t3.small"
  description = "EC2 Instance Type"
  validation {
    condition     = contains(["t1.micro", "t2.2xlarge", "t2.large", "t2.medium", "t2.micro", "t2.nano", "t2.small", "t2.xlarge", "t3.2xlarge", "t3.large", "t3.medium", "t3.micro", "t3.nano", "t3.small", "t3.xlarge", "t3a.2xlarge", "t3a.large", "t3a.medium", "t3a.micro", "t3a.nano", "t3a.small", "t3a.xlarge", "t4g.2xlarge", "t4g.large", "t4g.medium", "t4g.micro", "t4g.nano", "t4g.small", "t4g.xlarge"], var.instance_type)
    error_message = "InstanceType must be one of: t1.micro, t2.2xlarge, t2.large, t2.medium, t2.micro, t2.nano, t2.small, t2.xlarge, t3.2xlarge, t3.large, t3.medium, t3.micro, t3.nano, t3.small, t3.xlarge, t3a.2xlarge, t3a.large, t3a.medium, t3a.micro, t3a.nano, t3a.small, t3a.xlarge, t4g.2xlarge, t4g.large, t4g.medium, t4g.micro, t4g.nano, t4g.small, t4g.xlarge"
  }
}
variable "ssm_run_command_shell_script" {
  type        = string
  default     = ""
  description = "Systems Manager Run Command [AWS-RunShellScript]"
}
variable "ssm_command_wait_for_success_timeout_seconds" {
  type        = number
  default     = 300
  description = "If the association status doesn't show [Success] after the specified number of seconds, then stack creation fails."
}
# --- Mappings / Conditions ---
locals {
  mappings = {
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
  stack_id                  = "arn:${data.aws_partition.current.partition}:cloudformation:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:stack/${var.stack_name}/${random_uuid.stack_id.result}"
  cond_create_ssm_associate = (!(var.ssm_run_command_shell_script == ""))
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
resource "aws_iam_role_policy_attachment" "ops_ec2_iam_role" {
  role       = aws_iam_role.ops_ec2_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
# --- Resources ---
resource "aws_key_pair" "key_pair" {
  key_name   = join("-", ["key", element(split("-", element(split("/", local.stack_id), 2)), 4)])
  public_key = tls_private_key.key_pair.public_key_openssh
}
# CreationPolicy: CloudFormation CreationPolicy (cfn-signal) has no Terraform equivalent; the wait is not reproduced.
# # {
# #   "ResourceSignal": {
# #     "Count": "1",
# #     "Timeout": "PT10M"
# #   }
# # }
resource "aws_instance" "ops_ec2" {
  ami           = data.aws_ssm_parameter.ami_id.insecure_value
  instance_type = var.instance_type
  key_name      = aws_key_pair.key_pair.key_name
  tags = {
    Name = "vscode"
  }
  iam_instance_profile        = aws_iam_instance_profile.ops_ec2_instance_profile.name
  user_data                   = <<EOT
#!/bin/bash
dnf update -y
dnf install -y -q git
dnf groupinstall -y -q "Development Tools"
dnf install -y -q python3.12
python3.12 -m ensurepip --upgrade
python3.12 -m pip install --upgrade pip
ln -s /usr/bin/pip3.12 /usr/local/bin/pip
ln -s /usr/bin/python3.12 /usr/bin/python
wget -q https://github.com/coder/code-server/releases/download/v4.93.1/code-server-4.93.1-linux-amd64.tar.gz
tar -xzf code-server-4.93.1-linux-amd64.tar.gz
mv code-server-4.93.1-linux-amd64 /usr/local/lib/code-server
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
systemctl enable --now code-server
/opt/aws/bin/cfn-signal -e $? --stack ${var.stack_name} --resource OpsEc2 --region ${data.aws_region.current.region}
dnf install -y -q docker
systemctl enable --now docker
# usermod -aG docker ec2-user
# newgrp docker
## VS Code Server Terminal(Bash) Deletes "docker" group...
chmod 666 /var/run/docker.sock
EOT
  subnet_id                   = var.public_subnet_id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.ops_ec2_security_group.id]
}
resource "aws_security_group" "ops_ec2_security_group" {
  description = "Security Group for Ops EC2 SSH Connection"
  name        = join("-", ["ops-ec2-sg", element(split("-", element(split("/", local.stack_id), 2)), 4)])
  vpc_id      = var.vpc_id
  ingress {
    description     = "com.amazonaws.global.cloudfront.origin-facing"
    protocol        = "tcp"
    from_port       = 8000
    to_port         = 8000
    prefix_list_ids = [local.mappings["AWSRegions2PrefixListID"][data.aws_region.current.region]["PrefixList"]]
  }
}
resource "aws_iam_role" "ops_ec2_iam_role" {
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
resource "aws_iam_instance_profile" "ops_ec2_instance_profile" {
  role = jsonencode([aws_iam_role.ops_ec2_iam_role.name])
}
resource "aws_cloudfront_distribution" "cloud_front_distribution" {
  origin {
    domain_name = aws_instance.ops_ec2.public_dns
    origin_id   = aws_instance.ops_ec2.public_dns
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
    target_origin_id         = aws_instance.ops_ec2.public_dns
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
resource "aws_ssm_association" "ssm_association" {
  count                            = local.cond_create_ssm_associate ? 1 : 0
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.ssm_command_wait_for_success_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [aws_instance.ops_ec2.id]
  }
  parameters = {
    commands = join("\n", [var.ssm_run_command_shell_script])
  }
}
# --- Outputs ---
# CloudFormation output: CloudFrontDomainName
output "cloud_front_domain_name" {
  value = "https://${aws_cloudfront_distribution.cloud_front_distribution.domain_name}"
}
# CloudFormation output: Ec2InstanceId
output "ec2_instance_id" {
  value = aws_instance.ops_ec2.id
}
# CloudFormation output: Ec2IamRoleArn
output "ec2_iam_role_arn" {
  value = aws_iam_role.ops_ec2_iam_role.arn
}
# CloudFormation output: Ec2PublicIp
output "ec2_public_ip" {
  value = aws_instance.ops_ec2.public_ip
}
# CloudFormation output: Ec2PublicDnsName
output "ec2_public_dns_name" {
  value = aws_instance.ops_ec2.public_dns
}
# CloudFormation output: Ec2SecurityGroup
output "ec2_security_group" {
  value = aws_security_group.ops_ec2_security_group.id
}
