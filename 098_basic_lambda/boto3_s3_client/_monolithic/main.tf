# Generated from 098_basic_lambda/boto3_s3_client.yaml by tools/cfn2tf.
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
data "aws_caller_identity" "current" {}
# --- Parameters ---
variable "random_string" {
  type        = string
  description = "Random 4 Characters (a-z)"
}
# --- Resources split out of composite CloudFormation resources ---
resource "aws_s3_bucket_versioning" "s3_bucket_versioning" {
  bucket = aws_s3_bucket.s3_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}
resource "aws_s3_bucket_notification" "s3_bucket_notification" {
  bucket = aws_s3_bucket.s3_bucket.id
  lambda_function {
    events = ["s3:ObjectCreated:*"]
    # TODO cfn2tf: unmapped CloudFormation property 'Filter' of AWS::S3::Bucket
    # # {
    # #   "S3Key": {
    # #     "Rules": [
    # #       {
    # #         "Name": "prefix",
    # #         "Value": "incoming"
    # #       }
    # #     ]
    # #   }
    # # }
    lambda_function_arn = aws_lambda_function.lambda_function.arn
  }
}
data "archive_file" "lambda_function" {
  type        = "zip"
  source_file = "${path.module}/lambda_src/lambda_function/index.py"
  output_path = "${path.module}/build/lambda_function.zip"
}
resource "aws_iam_role_policy_attachment" "lambda_iam_role_0" {
  role       = aws_iam_role.lambda_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
resource "aws_iam_role_policy_attachment" "lambda_iam_role_1" {
  role       = aws_iam_role.lambda_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}
# --- Resources ---
resource "aws_s3_bucket" "s3_bucket" {
  bucket     = "sensitive-${var.random_string}"
  depends_on = [aws_lambda_permission.lambda_invoke_permission]
}
resource "aws_lambda_function" "lambda_function" {
  function_name    = "masking-start"
  runtime          = "python3.13"
  role             = aws_iam_role.lambda_iam_role.arn
  handler          = "index.lambda_handler"
  timeout          = 300
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
resource "aws_lambda_permission" "lambda_invoke_permission" {
  function_name  = aws_lambda_function.lambda_function.arn
  action         = "lambda:InvokeFunction"
  principal      = "s3.amazonaws.com"
  source_arn     = "arn:aws:s3:::sensitive-${var.random_string}"
  source_account = data.aws_caller_identity.current.account_id
}
