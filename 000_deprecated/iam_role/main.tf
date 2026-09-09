# Generated from 000_deprecated/iam_role.yaml by tools/cfn2tf.
# CloudFormation stack -> Terraform root module.
terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
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
# --- Resources split out of composite CloudFormation resources ---
resource "aws_iam_role_policy" "yaml_iam_role" {
  name = "GetS3Policy"
  role = aws_iam_role.yaml_iam_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:*", "s3-object-lambda:*"]
      Resource = "*"
    }]
  })
}
resource "aws_iam_role_policy" "json_iam_role" {
  name = "GetS3Policy"
  role = aws_iam_role.json_iam_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:*", "s3-object-lambda:*"]
      Resource = "*"
    }]
  })
}
resource "aws_iam_role_policy" "string_iam_role" {
  name   = "GetS3Policy"
  role   = aws_iam_role.string_iam_role.name
  policy = "{\n    \"Version\": \"2012-10-17\",\n    \"Statement\": [\n        {\n            \"Effect\": \"Allow\",\n            \"Action\": [\n                \"s3:*\",\n                \"s3-object-lambda:*\"\n            ],\n            \"Resource\": \"*\"\n        }\n    ]\n}"
}
# --- Resources ---
resource "aws_iam_role" "yaml_iam_role" {
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
resource "aws_iam_role" "json_iam_role" {
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
resource "aws_iam_role" "string_iam_role" {
  assume_role_policy = "{\n    \"Version\": \"2012-10-17\",\n    \"Statement\": [\n        {\n            \"Effect\": \"Allow\",\n            \"Principal\": {\n                \"Service\": \"ec2.amazonaws.com\"\n            },\n            \"Action\": \"sts:AssumeRole\"\n        }\n    ]\n}\n"
}
