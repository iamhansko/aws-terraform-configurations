# Generated from 094_ai_bedrock_lambda_kakao_chatbot/x-api-key/bedrock-chat/template.yaml by tools/cfn2tf.
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
# --- Mappings / Conditions ---
locals {
  mappings = {
    ResourceMap = {
      CallbackLambdaFunction = {
        Name = "bedrock-chat-callback-lambda"
      }
    }
  }
}
# --- Resources split out of composite CloudFormation resources ---
resource "aws_iam_role_policy" "kakao_chatbot_lambda_function_role" {
  name = "KakaoChatbotIamPolicy"
  role = aws_iam_role.kakao_chatbot_lambda_function_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["lambda:InvokeFunction", "lambda:InvokeAsync"]
      Resource = "*"
      }, {
      Effect   = "Allow"
      Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "*"
    }]
  })
}
resource "aws_iam_role_policy" "callback_lambda_function_role" {
  name = "CallbackIamPolicy"
  role = aws_iam_role.callback_lambda_function_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["lambda:InvokeFunction", "lambda:InvokeAsync"]
      Resource = "*"
      }, {
      Effect   = "Allow"
      Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "*"
      }, {
      Effect   = "Allow"
      Action   = ["bedrock:*"]
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
resource "aws_lambda_function" "kakao_chatbot_lambda_function" {
  handler     = "app.lambda_handler"
  runtime     = "python3.12"
  description = "Kakao Chatbot Function"
  role        = aws_iam_role.kakao_chatbot_lambda_function_role.arn
  filename    = "./src"
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  function_name = "${var.stack_name}-kakao-chatbot-lambda-function"
}
resource "aws_iam_role" "kakao_chatbot_lambda_function_role" {
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
resource "aws_api_gateway_rest_api" "api_gateway_rest_api" {
  # TODO cfn2tf: unmapped CloudFormation property 'StageName' of AWS::Serverless::Api
  # # "v1"
  # TODO cfn2tf: unmapped CloudFormation property 'OpenApiVersion' of AWS::Serverless::Api
  # # "2.0"
  # TODO cfn2tf: unmapped CloudFormation property 'Auth' of AWS::Serverless::Api
  # # {
  # #   "ApiKeyRequired": true,
  # #   "UsagePlan": {
  # #     "CreateUsagePlan": "PER_API"
  # #   }
  # # }
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  name = "${var.stack_name}-api-gateway-rest-api"
}
resource "aws_lambda_function" "callback_lambda_function" {
  function_name = local.mappings["ResourceMap"]["CallbackLambdaFunction"]["Name"]
  handler       = "callback.lambda_handler"
  runtime       = "python3.12"
  layers        = [aws_lambda_layer_version.lambda_layer.arn]
  description   = "Kakao Chatbot Callback Function"
  role          = aws_iam_role.callback_lambda_function_role.arn
  filename      = "./src"
}
resource "aws_iam_role" "callback_lambda_function_role" {
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
# --- Outputs ---
# CloudFormation output: KakaoChatbotFunction
output "kakao_chatbot_function" {
  value       = aws_lambda_function.kakao_chatbot_lambda_function.arn
  description = "Kakao Chatbot Function ARN"
}
# CloudFormation output: KakaoChatbotFunctionRole
output "kakao_chatbot_function_role" {
  value       = aws_iam_role.kakao_chatbot_lambda_function_role.arn
  description = "IAM Role for Kakao Chatbot Function"
}
# CloudFormation output: CallbackFunction
output "callback_function" {
  value       = aws_lambda_function.callback_lambda_function.arn
  description = "Kakao Chatbot Callback Function ARN"
}
# CloudFormation output: CallbackFunctionRole
output "callback_function_role" {
  value       = aws_iam_role.callback_lambda_function_role.arn
  description = "IAM Role for Kakao Chatbot Callback Function"
}
