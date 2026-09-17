terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
    tls = { source = "hashicorp/tls", version = "~> 4.0" }
  }
}
provider "aws" {
  region = var.aws_region
}
# No kubernetes, kubectl or helm provider, unlike the EKS projects in this
# repository: there is no cluster in this root module. That is also why the
# instance's bootstrap installs no kubectl, eksctl or helm by default - those
# five tools are required together only when an EKS cluster lives in the same
# root (rules.md H-1).
