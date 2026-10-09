terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}
provider "aws" {
  region = var.aws_region
}
# One provider, no aliases, even though a StackSet is the repository's clearest multi-region mechanism.
#
# That is the point of it: CloudFormation fans the template out across accounts and regions itself, so
# Terraform only has to create the StackSet in one place. Doing the same thing with aliased providers would
# be one provider block per region and a copy of every resource (rules.md I).
