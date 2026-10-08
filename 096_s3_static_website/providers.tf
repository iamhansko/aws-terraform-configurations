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
# The archive provider packages the two Python functions under lambda_src/ into zips. It is the same
# dependency the _monolithic file declared, and it is kept rather than replaced by inline source blocks
# because the sources on disk are the thing to read when working out what either function does.
#
# No random provider. The _monolithic template had nothing to generate, and the two names that would
# otherwise need uniquifying - the bucket and the instance profile - use S3's bucket_prefix and IAM's
# name_prefix instead, which the services generate suffixes for themselves.
