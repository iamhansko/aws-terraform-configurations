terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}
# No profile and no assume_role. Which account this applies to is decided by the credentials of whoever runs
# it, not by the configuration - that is what makes this a separate root from 2_source_account rather than
# one root with two aliased providers (rules.md I-1). The check below is what stops it landing in the wrong
# one.
provider "aws" {
  region = var.aws_region
}
