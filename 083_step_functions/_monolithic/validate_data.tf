# Generated from 083_step_functions/validate_data.yaml by tools/cfn2tf.
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
  default     = "validate-data"
  description = "Stands in for AWS::StackName."
}
# --- Resources split out of composite CloudFormation resources ---
resource "aws_iam_role_policy" "step_functions_role" {
  name = "StepFunctionsPolicy"
  role = aws_iam_role.step_functions_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["lambda:InvokeFunction", "sns:Publish", "logs:*"]
      Resource = "*"
    }]
  })
}
resource "aws_iam_role_policy_attachment" "step_functions_role" {
  role       = aws_iam_role.step_functions_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaRole"
}
resource "aws_iam_role_policy_attachment" "lambda_role" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
data "archive_file" "validate_data_function" {
  type        = "zip"
  source_file = "${path.module}/lambda_src/validate_data_function/index.py"
  output_path = "${path.module}/build/validate_data_function.zip"
}
data "archive_file" "process_data_function" {
  type        = "zip"
  source_file = "${path.module}/lambda_src/process_data_function/index.py"
  output_path = "${path.module}/build/process_data_function.zip"
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
      Action   = ["states:StartExecution"]
      Resource = "*"
    }]
  })
}
resource "aws_iam_role_policy_attachment" "custom_resource_lambda_iam_role" {
  role       = aws_iam_role.custom_resource_lambda_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
# --- Resources ---
resource "aws_iam_role" "step_functions_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "states.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
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
resource "aws_lambda_function" "validate_data_function" {
  runtime          = "python3.9"
  handler          = "index.lambda_handler"
  role             = aws_iam_role.lambda_role.arn
  filename         = data.archive_file.validate_data_function.output_path
  source_code_hash = data.archive_file.validate_data_function.output_base64sha256
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  function_name = "${var.stack_name}-validate-data-function"
}
resource "aws_lambda_function" "process_data_function" {
  runtime          = "python3.9"
  handler          = "index.lambda_handler"
  role             = aws_iam_role.lambda_role.arn
  filename         = data.archive_file.process_data_function.output_path
  source_code_hash = data.archive_file.process_data_function.output_base64sha256
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  function_name = "${var.stack_name}-process-data-function"
}
resource "aws_sns_topic" "sns_topic" {}
resource "aws_sfn_state_machine" "state_machine" {
  role_arn   = aws_iam_role.step_functions_role.arn
  definition = <<EOT
{
  "Comment": "name(String), age(PositiveInteger)",
  "StartAt": "ValidateData",
  "States": {
    "ValidateData": {
      "Type": "Task",
      "Resource": "${aws_lambda_function.validate_data_function.arn}",
      "Next": "IsValid"
    },
    "IsValid": {
      "Type": "Choice",
      "Choices": [
        {
          "Variable": "$.isValid",
          "BooleanEquals": true,
          "Next": "ProcessData"
        }
      ],
      "Default": "NotifyFailed"
    },
    "ProcessData": {
      "Type": "Task",
      "Resource": "${aws_lambda_function.process_data_function.arn}",
      "Next": "NotifySucceeded"
    },
    "NotifySucceeded": {
      "Type": "Task",
      "Resource": "arn:aws:states:::sns:publish",
      "Parameters": {
        "TopicArn": "${aws_sns_topic.sns_topic.arn}",
        "Message": "StepFunction Succeeded",
        "Subject": "SUCCEEDED"
      },
      "End": true
    },
    "NotifyFailed": {
      "Type": "Task",
      "Resource": "arn:aws:states:::sns:publish",
      "Parameters": {
        "TopicArn": "${aws_sns_topic.sns_topic.arn}",
        "Message": "StepFunction Failed",
        "Subject": "FAILED"
      },
      "End": true
    }
  }
}
EOT
}
resource "aws_lambda_invocation" "good_execution" {
  function_name = aws_lambda_function.custom_resource_lambda_function.arn
  input = jsonencode({
    StateMachine = aws_sfn_state_machine.state_machine.arn
    Input = {
      data = {
        name = "Gildong"
        age  = 25
      }
    }
  })
}
resource "aws_lambda_invocation" "bad_execution" {
  function_name = aws_lambda_function.custom_resource_lambda_function.arn
  input = jsonencode({
    StateMachine = aws_sfn_state_machine.state_machine.arn
    Input = {
      data = {
        name = "Hyunsu"
        age  = 0
      }
    }
  })
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
