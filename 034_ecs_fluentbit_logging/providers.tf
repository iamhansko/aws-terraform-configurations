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
# No random provider, which the _monolithic template required.
#
# It generated a random_uuid to stand in for AWS::StackId and then sliced a segment back out of it to make
# the key pair name and the container instance profile name unique. key_name_prefix on the key pair and
# name_prefix on the instance profile and the IAM policy get the same property from the provider itself,
# so the uuid and the provider are both gone.
#
# tls stays: it generates the key pair whose private half the key_pair module writes to Parameter Store.
