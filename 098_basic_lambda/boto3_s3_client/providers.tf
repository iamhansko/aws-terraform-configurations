terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
    # The function is deployed from source in this repository rather than from a
    # bucket, so the zip has to be built during the run. archive_file does it at
    # plan time, which is what makes a change to index.py show up as a plan diff
    # instead of being discovered on the next apply.
    archive = { source = "hashicorp/archive", version = "~> 2.4" }
  }
}
provider "aws" {
  region = var.aws_region
}
