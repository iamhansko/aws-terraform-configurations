# Generated from 064_s3_cross_account_replication_rule/2_source_account.yaml by tools/cfn2tf.
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
variable "destination_s3_bucket_name" {
  type = string
}
variable "destination_account_id" {
  type = string
}
# --- Resources split out of composite CloudFormation resources ---
resource "aws_s3_bucket_versioning" "source_s3_bucket_versioning" {
  bucket = aws_s3_bucket.source_s3_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}
resource "aws_s3_bucket_replication_configuration" "source_s3_bucket_replication" {
  bucket = aws_s3_bucket.source_s3_bucket.id
  role   = aws_iam_role.s3_replication_iam_role.arn
  rule {
    destination {
      account = var.destination_account_id
      bucket  = "arn:aws:s3:::${var.destination_s3_bucket_name}"
      metrics {
        status = "Enabled"
        event_threshold {
          minutes = 15
        }
      }
      replication_time {
        status = "Enabled"
        time {
          minutes = 15
        }
      }
    }
    filter {
      prefix = ""
    }
    priority = 0
    delete_marker_replication {
      status = "Enabled"
    }
    status = "Enabled"
  }
}
resource "aws_iam_role_policy" "s3_replication_iam_role" {
  name = "S3ReplicationIamPolicy"
  role = aws_iam_role.s3_replication_iam_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:ListBucket", "s3:GetReplicationConfiguration", "s3:GetObjectVersionForReplication", "s3:GetObjectVersionAcl", "s3:GetObjectVersionTagging", "s3:GetObjectRetention", "s3:GetObjectLegalHold", "s3:ReplicateObject", "s3:ReplicateDelete", "s3:ReplicateTags", "s3:ObjectOwnerOverrideToBucketOwner"]
      Resource = "*"
    }]
  })
}
# --- Resources ---
resource "aws_s3_bucket" "source_s3_bucket" {}
resource "aws_iam_role" "s3_replication_iam_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "s3.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}
# --- Outputs ---
# CloudFormation output: SourceS3Bucket
output "source_s3_bucket" {
  value = aws_s3_bucket.source_s3_bucket.id
}
