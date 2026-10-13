terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    # One wait closes IAM's eventual-consistency gap between PutRolePolicy returning and CodePipeline's
    # source action evaluating that policy.
    time = {
      source  = "hashicorp/time"
      version = "~> 0.14"
    }
    http = { source = "hashicorp/http", version = "~> 3.4" }
  }
}

provider "aws" {
  region = var.aws_region
}
