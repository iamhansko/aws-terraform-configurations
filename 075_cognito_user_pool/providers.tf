terraform {
  required_version = ">= 1.9"
  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 6.0" }
    archive = { source = "hashicorp/archive", version = "~> 2.4" }
    tls     = { source = "hashicorp/tls", version = "~> 4.0" }
  }
}
provider "aws" {
  region = var.aws_region
}
# random, which the _monolithic template declared, is gone with what used it. archive is back, for something
# other than what the template used it for.
#
# The template's archive zipped the custom resource Lambda that looked up the CloudFront origin-facing prefix
# list. That is a data source now (main.tf), and the Lambda never worked as a Terraform resource anyway.
# cfnresponse exists only for code CloudFormation inlines, so the zipped function failed at import. Past that,
# it read RequestType and ResourceProperties, which aws_lambda_invocation does not send, its except branch named
# an undefined variable, and it returned nothing - there was no PrefixListId for the security group rule to
# read. What archive zips now is the function that waits for the build's images (modules/ecr_image_waiter),
# which is invoked as a plain function and returns its result.
#
# random stood in for AWS::StackId, whose uuid fed the key pair name. The key pair takes a name prefix instead,
# and the buckets take bucket_prefix, so nothing needs a suffix generated here.
#
# tls generates the workbench key pair (modules/key_pair).
