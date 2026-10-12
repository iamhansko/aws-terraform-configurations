# Generated from 064_s3_cross_account_replication_rule/1_destination_account.yaml by tools/cfn2tf.
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
variable "source_account_id" {
  type = string
}
# --- Resources split out of composite CloudFormation resources ---
resource "aws_s3_bucket_versioning" "destination_s3_bucket_versioning" {
  bucket = aws_s3_bucket.destination_s3_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}
# --- Resources ---
resource "aws_s3_bucket" "destination_s3_bucket" {}
resource "aws_s3_bucket_policy" "destination_s3_bucket_policy" {
  bucket = aws_s3_bucket.destination_s3_bucket.id
  policy = jsonencode({
    Statement = [{
      Principal = {
        AWS = "arn:aws:iam::${var.source_account_id}:root"
      }
      Effect   = "Allow"
      Action   = ["s3:GetBucketVersioning", "s3:PutBucketVersioning", "s3:ReplicateObject", "s3:ReplicateDelete"]
      Resource = ["arn:aws:s3:::${aws_s3_bucket.destination_s3_bucket.id}", "arn:aws:s3:::${aws_s3_bucket.destination_s3_bucket.id}/*"]
    }]
  })
}
# --- Outputs ---
# CloudFormation output: DestinationS3Bucket
output "destination_s3_bucket" {
  value = aws_s3_bucket.destination_s3_bucket.id
}
