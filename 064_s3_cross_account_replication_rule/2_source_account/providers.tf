terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}
# No profile and no assume_role, for the same reason as the destination root: which account this lands in is
# the runner's credentials, not the configuration (rules.md I-1). expected_account_id is the guard.
provider "aws" {
  region = var.aws_region
}
