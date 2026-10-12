# Generated from 117_cloudformation_cross_account_s3_template/s3_bucket_policy_1_bucket_account.yaml by tools/cfn2tf.
# CloudFormation stack -> Terraform root module.
terraform {
  required_version = ">= 1.9"
  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 6.0" }
    archive = { source = "hashicorp/archive", version = "~> 2.4" }
    random  = { source = "hashicorp/random", version = "~> 3.6" }
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
  default     = "s3-bucket-policy-1-bucket-account"
  description = "Stands in for AWS::StackName."
}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}
# Provides the unique suffix that AWS::StackId supplies in CloudFormation.
resource "random_uuid" "stack_id" {}
# --- Parameters ---
variable "cloud_formation_iam_role_name" {
  type        = string
  default     = "CloudFormationIamRole"
  description = "CloudFormation IAM Role Name"
}
variable "cloud_formation_account_id" {
  type        = string
  description = "CloudFormation AWS Account ID"
}
# --- Mappings / Conditions ---
locals {
  stack_id = "arn:${data.aws_partition.current.partition}:cloudformation:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:stack/${var.stack_name}/${random_uuid.stack_id.result}"
}
# --- Resources split out of composite CloudFormation resources ---
data "archive_file" "lambda_function" {
  type        = "zip"
  source_file = "${path.module}/lambda_src/lambda_function/index.py"
  output_path = "${path.module}/build/lambda_function.zip"
}
resource "aws_iam_role_policy" "lambda_iam_role" {
  name = "S3TemplateUpload"
  role = aws_iam_role.lambda_iam_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:PutObject", "s3:DeleteObject"]
      Resource = "arn:${data.aws_partition.current.partition}:s3:::${aws_s3_bucket.s3_bucket.id}/*"
    }]
  })
}
resource "aws_iam_role_policy_attachment" "lambda_iam_role" {
  role       = aws_iam_role.lambda_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
# --- Resources ---
resource "aws_s3_bucket" "s3_bucket" {
  bucket = "cloudformation-templates-${var.stack_name}-${element(split("-", element(split("/", local.stack_id), 2)), 3)}"
}
resource "aws_s3_bucket_policy" "s3_bucket_policy" {
  bucket = aws_s3_bucket.s3_bucket.id
  policy = <<EOT
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowGetObject",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:${data.aws_partition.current.partition}:iam::${var.cloud_formation_account_id}:root"
      },
      "Action": [
        "s3:GetObject",
        "s3:GetObjectVersion"
      ],
      "Resource": "arn:${data.aws_partition.current.partition}:s3:::${aws_s3_bucket.s3_bucket.id}/*"
    },
    {
      "Sid": "AllowGetBucketLocation",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:${data.aws_partition.current.partition}:iam::${var.cloud_formation_account_id}:root"
      },
      "Action": "s3:GetBucketLocation",
      "Resource": "arn:${data.aws_partition.current.partition}:s3:::${aws_s3_bucket.s3_bucket.id}"
    }
  ]
}
EOT
}
resource "aws_lambda_invocation" "upload_template" {
  function_name = aws_lambda_function.lambda_function.arn
  input = jsonencode({
    S3Bucket     = aws_s3_bucket.s3_bucket.id
    S3ObjectKey  = "template.yaml"
    TemplateBody = "Resources:\n  Vpc:\n    Type: AWS::EC2::VPC\n    Properties:\n      CidrBlock: 10.0.0.0/16\n      EnableDnsSupport: true\n      EnableDnsHostnames: true\n      Tags:\n        - Key: Name\n          Value: new-vpc\n"
  })
}
resource "aws_lambda_function" "lambda_function" {
  runtime          = "python3.14"
  handler          = "index.handler"
  timeout          = 30
  role             = aws_iam_role.lambda_iam_role.arn
  filename         = data.archive_file.lambda_function.output_path
  source_code_hash = data.archive_file.lambda_function.output_base64sha256
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  function_name = "${var.stack_name}-lambda-function"
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
# --- Outputs ---
# CloudFormation output: S3BucketName
output "s3_bucket_name" {
  value       = aws_s3_bucket.s3_bucket.id
  description = "Template S3 Bucket Name"
}
