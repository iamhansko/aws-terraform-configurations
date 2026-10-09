# Generated from 029_aws_config_rule_custom_lambda/instance_profile_governance.yaml by tools/cfn2tf.
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
  default     = "instance-profile-governance"
  description = "Stands in for AWS::StackName."
}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}
# Provides the unique suffix that AWS::StackId supplies in CloudFormation.
resource "random_uuid" "stack_id" {}
# --- Parameters ---
variable "default_vpc_id" {
  type = string
}
variable "default_vpc_public_subnet_id" {
  type = string
}
variable "bastion_ec2_ami_id" {
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
  description = "(SSM parameter path; resolved by the aws_ssm_parameter data source)"
}
data "aws_ssm_parameter" "bastion_ec2_ami_id" {
  name = var.bastion_ec2_ami_id
}
# --- Mappings / Conditions ---
locals {
  stack_id = "arn:${data.aws_partition.current.partition}:cloudformation:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:stack/${var.stack_name}/${random_uuid.stack_id.result}"
}
# --- Resources split out of composite CloudFormation resources ---
resource "aws_iam_role_policy_attachment" "bastion_ec2_role_0" {
  role       = aws_iam_role.bastion_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
resource "aws_iam_role_policy_attachment" "bastion_ec2_role_1" {
  role       = aws_iam_role.bastion_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/IAMFullAccess"
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
resource "aws_iam_role_policy_attachment" "config_service_role" {
  role       = aws_iam_role.config_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
data "archive_file" "lambda_function" {
  type        = "zip"
  source_file = "${path.module}/lambda_src/lambda_function/index.py"
  output_path = "${path.module}/build/lambda_function.zip"
}
resource "aws_iam_role_policy" "lambda_role" {
  name = "AttachOnly-AmazonS3ReadOnlyAccess"
  role = aws_iam_role.lambda_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["iam:GetInstanceProfile", "iam:ListAttachedRolePolicies", "iam:DetachRolePolicy", "iam:AttachRolePolicy", "config:PutEvaluations"]
      Resource = "*"
      }, {
      Effect   = "Allow"
      Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "arn:aws:logs:*:*:*"
    }]
  })
}
resource "aws_iam_role_policy_attachment" "governance_role1" {
  role       = aws_iam_role.governance_role1.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
# --- Resources ---
# CreationPolicy: CloudFormation CreationPolicy (cfn-signal) has no Terraform equivalent; the wait is not reproduced.
# # {
# #   "ResourceSignal": {
# #     "Count": "1",
# #     "Timeout": "PT5M"
# #   }
# # }
resource "aws_instance" "bastion_ec2" {
  iam_instance_profile = aws_iam_instance_profile.bastion_ec2_instance_profile.name
  ami                  = data.aws_ssm_parameter.bastion_ec2_ami_id.insecure_value
  instance_type        = "t3.micro"
  key_name             = aws_key_pair.key_pair.key_name
  tags = {
    Name = "governance-bastion"
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

/opt/aws/bin/cfn-signal -e $? --stack ${var.stack_name} --resource BastionEc2 --region ${data.aws_region.current.region}
EOT
  subnet_id                   = var.default_vpc_public_subnet_id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.bastion_ec2_security_group.id]
}
resource "aws_security_group" "bastion_ec2_security_group" {
  description = "Security Group"
  vpc_id      = var.default_vpc_id
  ingress {
    protocol    = "tcp"
    from_port   = 22
    to_port     = 22
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    protocol    = "tcp"
    from_port   = 8000
    to_port     = 8000
    cidr_blocks = ["0.0.0.0/0"]
  }
}
resource "aws_iam_role" "bastion_ec2_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}
resource "aws_iam_instance_profile" "bastion_ec2_instance_profile" {
  name = "BastionEc2InstanceProfile"
  # An instance profile holds at most one role, so this attribute is a single
  # role name string - not the list CloudFormation's AWS::IAM::InstanceProfile
  # Roles property takes. jsonencode([...]) here sends the literal string
  # ["terraform-..."] as roleName, which IAM rejects with a ValidationError
  # during apply, while terraform validate and plan both pass because the
  # attribute is a string either way (rules.md A-3).
  role = aws_iam_role.bastion_ec2_role.name
}
resource "aws_key_pair" "key_pair" {
  key_name   = "key-${element(split("-", element(split("/", local.stack_id), 2)), 3)}"
  public_key = tls_private_key.key_pair.public_key_openssh
}
resource "aws_config_config_rule" "config_rule" {
  name = "governance-role"
  scope {
    compliance_resource_types = ["AWS::EC2::Instance"]
  }
  source {
    owner             = "CUSTOM_LAMBDA"
    source_identifier = aws_lambda_function.lambda_function.arn
    source_detail {
      event_source = "aws.config"
      message_type = "ConfigurationItemChangeNotification"
    }
    source_detail {
      event_source = "aws.config"
      message_type = "OversizedConfigurationItemChangeNotification"
    }
  }
  depends_on = [aws_lambda_permission.lambda_permission]
}
resource "aws_config_configuration_recorder" "config_recorder" {
  name = "default"
  recording_group {
    all_supported                 = false
    include_global_resource_types = false
    resource_types                = []
    exclusion_by_resource_types {
      resource_types = ["AWS::IAM::Policy", "AWS::IAM::User", "AWS::IAM::Role", "AWS::IAM::Group"]
    }
    recording_strategy {
      use_only = "EXCLUSION_BY_RESOURCE_TYPES"
    }
  }
  recording_mode {
    recording_frequency = "CONTINUOUS"
  }
  role_arn = aws_iam_role.config_service_role.arn
}
resource "aws_iam_role" "config_service_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "config.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}
resource "aws_config_delivery_channel" "delivery_channel" {
  # TODO cfn2tf: unmapped CloudFormation property 'ConfigSnapshotDeliveryProperties' of AWS::Config::DeliveryChannel
  # # {
  # #   "DeliveryFrequency": "One_Hour"
  # # }
  s3_bucket_name = aws_s3_bucket.config_bucket.id
}
resource "aws_s3_bucket" "config_bucket" {}
resource "aws_lambda_permission" "lambda_permission" {
  function_name  = aws_lambda_function.lambda_function.function_name
  action         = "lambda:InvokeFunction"
  principal      = "config.amazonaws.com"
  source_account = data.aws_caller_identity.current.account_id
  source_arn     = "arn:aws:config:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:config-rule/*"
}
resource "aws_lambda_function" "lambda_function" {
  function_name = "governance-lambda"
  runtime       = "python3.13"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.lambda_handler"
  timeout       = 60
  logging_config {
    log_group = "/korea/governance/cloudwatch"
    # cfn2tf: 'log_format' is required by aws_lambda_function but absent from the CloudFormation template; using a provider-compatible default.
    log_format = "Text"
  }
  filename         = data.archive_file.lambda_function.output_path
  source_code_hash = data.archive_file.lambda_function.output_base64sha256
}
resource "aws_iam_role" "lambda_role" {
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
resource "aws_iam_instance_profile" "governance_instance_profile1" {
  name = "governance-instance-profile-1"
  # Single role name string, not a list (rules.md A-3).
  role = aws_iam_role.governance_role1.name
}
resource "aws_iam_role" "governance_role1" {
  name = "governance-instance-profile-1"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}
resource "aws_iam_instance_profile" "governance_instance_profile2" {
  name = "governance-instance-profile-2"
  # Single role name string, not a list (rules.md A-3).
  role = aws_iam_role.governance_role2.name
}
resource "aws_iam_role" "governance_role2" {
  name = "governance-instance-profile-2"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}
