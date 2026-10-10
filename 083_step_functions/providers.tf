terraform {
  required_version = ">= 1.9"
  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 6.0" }
    archive = { source = "hashicorp/archive", version = "~> 2.4" }
  }
}
provider "aws" {
  region = var.aws_region
}
# archive for packaging the three Lambda functions from lambda_src/. It runs at plan time, so a change to a
# function's source shows up as a change in plan rather than being discovered on the next apply.
