# Generated from 117_cloudformation_cross_account_s3_template/s3_bucket_policy_2_stack_account.yaml by tools/cfn2tf.
# CloudFormation stack -> Terraform root module.
terraform {
  required_version = ">= 1.9"
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
data "aws_region" "current" {}
# --- Parameters ---
variable "s3_bucket_name" {
  type        = string
  description = "Template S3 Bucket Name"
}
# --- Resources split out of composite CloudFormation resources ---
resource "aws_iam_role_policy_attachment" "cloud_formation_iam_role" {
  role       = aws_iam_role.cloud_formation_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
# --- Resources ---
resource "aws_iam_role" "cloud_formation_iam_role" {
  name = "CloudFormationIamRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "cloudformation.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}
# --- Outputs ---
# CloudFormation output: CreateStackCommand
output "create_stack_command" {
  value       = "aws cloudformation create-stack --stack-name my-stack --template-url https://${var.s3_bucket_name}.s3.${data.aws_region.current.region}.amazonaws.com/template.yaml --role-arn ${aws_iam_role.cloud_formation_iam_role.arn} --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND"
  description = "CloudFormation CreateStack AWS CLI Command"
}
