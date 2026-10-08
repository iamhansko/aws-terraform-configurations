terraform {
  required_version = ">= 1.9"
  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 6.0" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
  }
}
provider "aws" {
  region = var.aws_region
}
# The random provider is still here but does a different job than in the _monolithic template. That template
# generated a uuid to stand in for AWS::StackId, purely so it could slice a suffix out of it and build a
# unique bucket name; S3's own bucket_prefix does that. Here it generates the Referer secret that keeps the
# publicly readable website endpoint from being useful to anyone who finds it.
#
# No provider aliased to us-east-1, which a CloudFront project often needs. That is for an ACM certificate
# for a custom domain, and this distribution uses the default *.cloudfront.net certificate - the
# distribution resource itself is global and can be created from any region.
