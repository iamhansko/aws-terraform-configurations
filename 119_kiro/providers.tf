terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    # AWS::SSO::Instance is not exposed by hashicorp/aws. AWSCC maps the CloudFormation/Cloud Control
    # resource so this root can create a standalone-account Identity Center instance when discovery is empty.
    awscc = {
      source  = "hashicorp/awscc"
      version = "1.105.0"
    }
  }
}

# Both providers use the same explicit region input. With aws_region=null they follow the same AWS provider
# environment chain, including AWS_DEFAULT_REGION, so discovery and optional creation cannot drift apart.
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = var.tags
  }
}

provider "awscc" {
  region = var.aws_region
}
