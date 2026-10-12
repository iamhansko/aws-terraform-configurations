terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}
# No profile and no assume_role: this root is applied with the stack account's own credentials, and the
# bucket account is a separate root with its own state (rules.md I-1). A precondition in main.tf refuses the
# wrong account.
provider "aws" {
  region = var.aws_region
}
