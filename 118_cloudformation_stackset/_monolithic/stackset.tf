# Generated from 118_cloudformation_stackset/stackset.yaml by tools/cfn2tf.
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
data "aws_caller_identity" "current" {}
# --- Resources split out of composite CloudFormation resources ---
resource "aws_iam_role_policy" "admin_account_iam_role" {
  name = "AssumeRole-AWSCloudFormationStackSetExecutionRole"
  role = aws_iam_role.admin_account_iam_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sts:AssumeRole"]
      Resource = ["arn:*:iam::*:role/${aws_iam_role.target_account_iam_role.name}"]
    }]
  })
}
resource "aws_iam_role_policy_attachment" "target_account_iam_role" {
  role       = aws_iam_role.target_account_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
# --- Resources ---
resource "aws_cloudformation_stack_set" "stack_set" {
  name                    = "AccessPolicy"
  administration_role_arn = aws_iam_role.admin_account_iam_role.arn
  execution_role_name     = "AWSCloudFormationStackSetExecutionRole"
  capabilities            = ["CAPABILITY_IAM", "CAPABILITY_NAMED_IAM", "CAPABILITY_AUTO_EXPAND"]
  permission_model        = "SELF_MANAGED"
  tags = {
    foo = "bar"
  }
  parameters = {}
  # TODO cfn2tf: unmapped CloudFormation property 'StackInstancesGroup' of AWS::CloudFormation::StackSet
  # # [
  # #   {
  # #     "DeploymentTargets": {
  # #       "Accounts": [
  # #         {
  # #           "Ref": "AWS::AccountId"
  # #         }
  # #       ]
  # #     },
  # #     "ParameterOverrides": [
  # #       {
  # #         "ParameterKey": "AllowedSourceIpAddresses",
  # #         "ParameterValue": "100.0.0.11,100.0.0.12,100.0.0.13,100.0.0.14"
  # #       }
  # #     ],
  # #     "Regions": [
  # #       {
  # #         "Ref": "AWS::Region"
  # #       }
  # #     ]
  # #   }
  # # ]
  template_body = "Parameters:\n  AllowedSourceIpAddresses:\n    Type: CommaDelimitedList\n    Description: Source IP Addresses\n    Default: 100.0.0.11,100.0.0.12\nResources:\n  DenyAllIamPolicy:\n    Type: AWS::IAM::ManagedPolicy\n    Properties:\n      ManagedPolicyName: DenyAll\n      PolicyDocument:\n        Version: 2012-10-17\n        Statement:\n          - Effect: Deny\n            Action: \"*\"\n            Resource: \"*\"\n            Condition:\n              NotIpAddress:\n                aws:SourceIp: !Ref AllowedSourceIpAddresses\n              Bool:\n                aws:ViaAWSService: \"false\"\n"
}
resource "aws_iam_role" "admin_account_iam_role" {
  name = "AWSCloudFormationStackSetAdministrationRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "cloudformation.amazonaws.com"
      }
      Action = ["sts:AssumeRole"]
    }]
  })
}
resource "aws_iam_role" "target_account_iam_role" {
  name = "AWSCloudFormationStackSetExecutionRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = data.aws_caller_identity.current.account_id
      }
      Action = ["sts:AssumeRole"]
    }]
  })
}
