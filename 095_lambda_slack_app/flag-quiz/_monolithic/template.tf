# Generated from 095_lambda_slack_app/flag-quiz/template.yaml by tools/cfn2tf.
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
  default     = "template"
  description = "Stands in for AWS::StackName."
}
# --- Parameters ---
variable "slack_client_id" {
  type    = string
  default = ""
}
variable "slack_client_secret" {
  type    = string
  default = ""
}
variable "slack_signing_secret" {
  type    = string
  default = ""
}
# --- Resources split out of composite CloudFormation resources ---
resource "aws_iam_role_policy" "aws_lambda_slack_app_function_role" {
  name = "SlackAppFunctionPolicy"
  role = aws_iam_role.aws_lambda_slack_app_function_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["lambda:InvokeFunction", "lambda:InvokeAsync"]
      Resource = "*"
      }, {
      Effect   = "Allow"
      Action   = ["s3:ListBucket", "s3:GetObject", "s3:GetObjectAcl", "s3:PutObject", "s3:PutObjectAcl", "s3:ReplicateObject", "s3:DeleteObject"]
      Resource = [aws_s3_bucket.oauth_state_s3_bucket.arn, "${aws_s3_bucket.oauth_state_s3_bucket.arn}/*", aws_s3_bucket.installation_s3_bucket.arn, "${aws_s3_bucket.installation_s3_bucket.arn}/*"]
      }, {
      Effect   = "Allow"
      Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "*"
    }]
  })
}
data "archive_file" "lambda_layer" {
  type        = "zip"
  source_dir  = "${path.module}/layer.zip"
  output_path = "${path.module}/build/lambda_layer.zip"
}
# --- Resources ---
resource "aws_s3_bucket" "oauth_state_s3_bucket" {}
resource "aws_s3_bucket" "installation_s3_bucket" {}
resource "aws_iam_role" "aws_lambda_slack_app_function_role" {
  name = "AWSLambdaSlackAppFunctionRole"
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
resource "aws_lambda_layer_version" "lambda_layer" {
  layer_name          = "LambdaLayer"
  description         = "Python Lambda Layer"
  compatible_runtimes = ["python3.12"]
  filename            = data.archive_file.lambda_layer.output_path
  source_code_hash    = data.archive_file.lambda_layer.output_base64sha256
}
resource "aws_lambda_function" "aws_lambda_slack_app_function" {
  handler     = "app.lambda_handler"
  runtime     = "python3.12"
  layers      = [aws_lambda_layer_version.lambda_layer.arn]
  description = "Slack App Function"
  role        = aws_iam_role.aws_lambda_slack_app_function_role.arn
  filename    = "./src"
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  function_name = "${var.stack_name}-aws-lambda-slack-app-function"
}
# --- Outputs ---
# CloudFormation output: OauthStateS3Bucket
output "oauth_state_s3_bucket" {
  value       = aws_s3_bucket.oauth_state_s3_bucket.arn
  description = "Oauth State S3 Bucket"
}
# CloudFormation output: InstallationS3Bucket
output "installation_s3_bucket" {
  value       = aws_s3_bucket.installation_s3_bucket.arn
  description = "Installation S3 Bucket"
}
# CloudFormation output: SlackAppFunction
output "slack_app_function" {
  value       = aws_lambda_function.aws_lambda_slack_app_function.arn
  description = "Slack App Function ARN"
}
# CloudFormation output: SlackAppFunctionRole
output "slack_app_function_role" {
  value       = aws_iam_role.aws_lambda_slack_app_function_role.arn
  description = "IAM Role for Slack App Function"
}
