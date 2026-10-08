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
# It used random_uuid to stand in for AWS::StackId and sliced a segment back out of it to make the key pair,
# the KMS alias and the bucket unique. key_name_prefix, an alias named after the stream and bucket_prefix do
# the same job, so the uuid and the provider are both gone.
#
# tls stays: it generates the key pair whose private half the key_pair module writes to Parameter Store.
