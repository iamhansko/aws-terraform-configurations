terraform {
  required_version = ">= 1.9"
  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 6.0" }
    archive = { source = "hashicorp/archive", version = "~> 2.4" }
    tls     = { source = "hashicorp/tls", version = "~> 4.0" }
    http    = { source = "hashicorp/http", version = "~> 3.4" }
  }
}
provider "aws" {
  region = var.aws_region
}
# No random provider, which the _monolithic template required to stand in for AWS::StackId. Its only use was
# making the bucket and key pair names unique, which bucket_prefix and key_name_prefix do.
#
# archive stays, for the presigning function - the one Lambda here that does something Terraform cannot.
# tls stays, for the workbench key pair.
