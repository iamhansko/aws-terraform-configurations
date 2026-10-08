terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}
provider "aws" {
  region = var.aws_region
}
# No random provider, which the _monolithic template of several of these projects carries. It generated a
# uuid to stand in for AWS::StackId so that a CloudFormation-generated name could be reproduced; nothing
# here needs a generated name, because the one resource that needs to avoid collisions uses IAM's own
# name_prefix instead.
