terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}
# Control Tower is driven from the organization's management account, and the
# landing zone's home Region is whichever Region this provider points at. That
# Region must also appear in governed_regions, or the mandatory Region deny
# policy would lock out the account that manages the landing zone.
provider "aws" {
  region = var.aws_region
}
