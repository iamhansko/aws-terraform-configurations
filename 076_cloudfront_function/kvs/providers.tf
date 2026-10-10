terraform {
  required_version = ">= 1.9"
  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 6.0" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
    tls    = { source = "hashicorp/tls", version = "~> 4.0" }
  }
}
# One provider. CloudFront Functions are global and are created through the provider's own region, unlike
# Lambda@Edge, which has to be in us-east-1 (see 077_cloudfront_lambda_edge).
provider "aws" {
  region = var.aws_region
}
# random stays, for a different job than in the _monolithic template. There it stood in for AWS::StackId and
# a slice of the uuid made the names unique; here random_id does the same thing directly. CloudFront Function
# and key value store names are unique per account, not per region, so a fixed name collides with the other
# variant of this project and with a second copy of this one.
#
# tls stays, for the workbench key pair.
