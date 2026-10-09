# Generated from 118_cloudformation_stackset/templates/iam_policy.yaml by tools/cfn2tf.
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
# --- Parameters ---
variable "allowed_source_ip_addresses" {
  type        = list(string)
  default     = ["100.0.0.11", "100.0.0.12"]
  description = "Source IP Addresses"
}
# --- Resources ---
resource "aws_iam_policy" "deny_all_iam_policy" {
  name = "DenyAll"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Deny"
      Action   = "*"
      Resource = "*"
      Condition = {
        NotIpAddress = {
          "aws:SourceIp" = var.allowed_source_ip_addresses
        }
        Bool = {
          "aws:ViaAWSService" = "false"
        }
      }
    }]
  })
}
