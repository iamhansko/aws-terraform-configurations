# Generated from 096_s3_static_website/escape_room.yaml by tools/cfn2tf.
# CloudFormation stack -> Terraform root module.
terraform {
  required_version = ">= 1.9"
  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 6.0" }
    archive = { source = "hashicorp/archive", version = "~> 2.4" }
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
  default     = "escape-room"
  description = "Stands in for AWS::StackName."
}
data "aws_region" "current" {}
# --- Parameters ---
variable "amazon_linux2023_ami_id" {
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
  description = "(SSM parameter path; resolved by the aws_ssm_parameter data source)"
}
data "aws_ssm_parameter" "amazon_linux2023_ami_id" {
  name = var.amazon_linux2023_ami_id
}
variable "game_source_url" {
  type    = string
  default = "https://github.com/iamhansko/escape-room-workshop/releases/download/test/game.zip"
}
variable "game_password" {
  type      = string
  default   = "988"
  sensitive = true
}
# --- Resources split out of composite CloudFormation resources ---
resource "aws_s3_bucket_website_configuration" "s3_bucket_website" {
  bucket = aws_s3_bucket.s3_bucket.id
  index_document {
    suffix = "index.html"
  }
  error_document {
    key = "error.html"
  }
}
resource "aws_s3_bucket_public_access_block" "s3_bucket_pab" {
  bucket                  = aws_s3_bucket.s3_bucket.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}
data "archive_file" "lambda_function" {
  type        = "zip"
  source_file = "${path.module}/lambda_src/lambda_function/index.py"
  output_path = "${path.module}/build/lambda_function.zip"
}
resource "aws_iam_role_policy_attachment" "lambda_iam_role" {
  role       = aws_iam_role.lambda_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
resource "aws_iam_role_policy_attachment" "bastion_ec2_iam_role" {
  role       = aws_iam_role.bastion_ec2_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
data "archive_file" "custom_resource_lambda_function" {
  type        = "zip"
  source_file = "${path.module}/lambda_src/custom_resource_lambda_function/index.py"
  output_path = "${path.module}/build/custom_resource_lambda_function.zip"
}
resource "aws_iam_role_policy" "custom_resource_lambda_iam_role" {
  name = "CustomLambdaPolicy"
  role = aws_iam_role.custom_resource_lambda_iam_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ec2:*"]
      Resource = "*"
    }]
  })
}
resource "aws_iam_role_policy_attachment" "custom_resource_lambda_iam_role" {
  role       = aws_iam_role.custom_resource_lambda_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
# --- Resources ---
resource "aws_s3_bucket" "s3_bucket" {}
resource "aws_s3_bucket_policy" "s3_bucket_policy" {
  policy = jsonencode({
    Id      = "MyPolicy"
    Version = "2012-10-17"
    Statement = [{
      Sid       = "PublicGet"
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.s3_bucket.arn}/*"
    }]
  })
  bucket = aws_s3_bucket.s3_bucket.id
}
resource "aws_lambda_function" "lambda_function" {
  function_name    = "Backend"
  handler          = "index.lambda_handler"
  role             = aws_iam_role.lambda_iam_role.arn
  runtime          = "python3.13"
  timeout          = 60
  filename         = data.archive_file.lambda_function.output_path
  source_code_hash = data.archive_file.lambda_function.output_base64sha256
}
resource "aws_iam_role" "lambda_iam_role" {
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
resource "aws_lambda_function_url" "lambda_function_url" {
  authorization_type = "NONE"
  cors {
    allow_origins = ["*"]
  }
  invoke_mode   = "BUFFERED"
  function_name = aws_lambda_function.lambda_function.arn
}
resource "aws_lambda_permission" "lambda_function_permission" {
  action                 = "lambda:invokeFunctionUrl"
  function_name          = aws_lambda_function.lambda_function.function_name
  function_url_auth_type = "NONE"
  principal              = "*"
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
# CreationPolicy: CloudFormation CreationPolicy (cfn-signal) has no Terraform equivalent; the wait is not reproduced.
# # {
# #   "ResourceSignal": {
# #     "Count": "1",
# #     "Timeout": "PT10M"
# #   }
# # }
resource "aws_instance" "bastion_ec2" {
  ami           = data.aws_ssm_parameter.amazon_linux2023_ami_id.insecure_value
  instance_type = "t3.medium"
  tags = {
    Name = "bastion-ec2"
  }
  iam_instance_profile        = aws_iam_instance_profile.bastion_ec2_instance_profile.name
  user_data                   = <<EOT
#!/bin/bash
dnf update -yq
dnf install -yq git
dnf groupinstall -yq "Development Tools"
dnf install -yq python3.13
ln -sf /usr/bin/python3.13 /usr/bin/python
python -m ensurepip --upgrade
echo 'import boto3
import requests
import zipfile
import io
import os
TYPE_MAP = {
  "html": "text/html",
  "css": "text/css",
  "js": "text/javascript",
  "txt": "text/plain",
  "sh": "text/x-sh",
  "png": "image/png",
  "jpg": "image/jpeg",
  "webp": "image/webp",
  "svg": "image/svg+xml",
  "gif": "image/gif",
  "json": "application/json"
}
S3_BUCKET = "${aws_s3_bucket.s3_bucket.id}"
SRC_URL = "${var.game_source_url}"
try:
  response = requests.get(SRC_URL)
  response.raise_for_status()
  s3 = boto3.client("s3")
  with zipfile.ZipFile(io.BytesIO(response.content)) as zf:
    for file_name in zf.namelist():
      if zf.getinfo(file_name).is_dir():
        continue
      file_data = zf.read(file_name)
      s3.put_object(
        Bucket=S3_BUCKET,
        Key=file_name,
        Body=file_data,
        ContentType=TYPE_MAP[file_name.split(".")[-1]]
      )
  s3.put_object(
    Bucket=S3_BUCKET,
    Key="data/lambda.json",
    Body="{\"url\" : \"${aws_lambda_function_url.lambda_function_url.function_url}\"}",
    ContentType="application/json"
  )
  hint_image = requests.get("https://github.com/iamhansko/escape-room-workshop/raw/refs/heads/main/img/hint1.png")
  hint_image.raise_for_status()
  s3.put_object(
    Bucket=S3_BUCKET,
    Key="hints/hint1.png",
    Body=hint_image.content,
    ContentType="image/png"
  )
  s3.put_object(
    Bucket=S3_BUCKET,
    Key="hints/hint2.txt",
    Body="교실에 꽃 한 송이가 숨겨져 있다.\n\n비밀번호의 1번째 자리는\n\n빨강꽃이라면 2\n파랑꽃이라면 9\n노랑꽃이라면 3\n분홍꽃이라면 4",
    ContentType="text/plain; charset=utf-8"
  )
  s3.put_object(
    Bucket=S3_BUCKET,
    Key="hints/hint3.txt",
    Body="비밀번호는 총 3자리이다.\n2번째 자리는 8이다.",
    ContentType="text/plain; charset=utf-8"
  )
  s3.put_object(
    Bucket=S3_BUCKET,
    Key="hints/hint4.txt",
    Body="비밀번호의 마지막 자리는\n정육면체의 [꼭짓점 수]와 동일한 숫자이다.",
    ContentType="text/plain; charset=utf-8"
  )
except Exception as e:
  print(e)' > index.py
cat index.py
python -m pip install requests boto3
python index.py
/opt/aws/bin/cfn-signal -e $? --stack ${var.stack_name} --resource BastionEc2 --region ${data.aws_region.current.region}
EOT
  subnet_id                   = aws_subnet.public_subnet.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_vpc.vpc.default_security_group_id]
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
}
resource "aws_iam_instance_profile" "bastion_ec2_instance_profile" {
  # name_prefix, not name. Instance profile names are account-wide, and this literal was shared with
  # 031_ecs_alb_integration, 035_codepipeline_ecs_bluegreen and 100_iam_roles_anywhere - the second of them
  # applied into an account fails on EntityAlreadyExists. The role above has no explicit name, so only this
  # one needed it (rules.md G-3).
  name_prefix = "Ec2AdminProfile-"
  # Hand edit, not conversion output. CloudFormation's AWS::IAM::InstanceProfile takes a Roles list, so the
  # conversion wrote jsonencode([...]) - but this attribute is a single role name, a profile holds at most one
  # role, and a JSON array string is not a role name. validate and plan pass; the apply fails in IAM
  # (rules.md A-3).
  role = aws_iam_role.bastion_ec2_iam_role.name
}
resource "aws_lambda_invocation" "terminate_bastion_ec2" {
  function_name = aws_lambda_function.custom_resource_lambda_function.arn
  input         = jsonencode({})
  depends_on    = [aws_instance.bastion_ec2]
}
resource "aws_lambda_function" "custom_resource_lambda_function" {
  handler          = "index.lambda_handler"
  role             = aws_iam_role.custom_resource_lambda_iam_role.arn
  runtime          = "python3.13"
  timeout          = 60
  filename         = data.archive_file.custom_resource_lambda_function.output_path
  source_code_hash = data.archive_file.custom_resource_lambda_function.output_base64sha256
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  function_name = "${var.stack_name}-custom-resource-lambda-function"
}
resource "aws_iam_role" "custom_resource_lambda_iam_role" {
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
# CloudFormation output: WebsiteURL
output "website_url" {
  value       = aws_s3_bucket.s3_bucket.website_endpoint
  description = "S3 Static Website"
}
