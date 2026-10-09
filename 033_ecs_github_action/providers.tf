terraform {
  required_version = ">= 1.9"
  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 6.0" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
    tls    = { source = "hashicorp/tls", version = "~> 4.0" }
  }
}
provider "aws" {
  region = var.aws_region
}
# tls generates the key pair whose private half the key_pair module writes to Parameter Store.
#
# random stays too, unlike most conversions in this repository, and it is worth saying why. The
# _monolithic template generated a random_uuid to stand in for AWS::StackId and then sliced a segment back
# out of it to make three names unique: the key pair, the source bucket and the CodeBuild project. Two of
# those have a provider-side answer - key_name_prefix and bucket_prefix - but a CodeBuild project name does
# not, and it is account-and-region unique. A single random_id covers it, and the generated workflow's
# runs-on label is built from the resulting project name rather than from the suffix, so the two cannot
# drift apart (rules.md B-5).
