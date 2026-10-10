terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
    tls = { source = "hashicorp/tls", version = "~> 4.0" }
    # Zips the handler of modules/ecr_image_waiter, the function that holds CreateFunction until the
    # workbench's push is in ECR.
    archive = { source = "hashicorp/archive", version = "~> 2.4" }
  }
}
provider "aws" {
  region = var.aws_region
}
# tls generates the key pair whose private half modules/key_pair writes to Parameter Store, the way
# CloudFormation does for a key pair it generates.
#
# random is gone. The _monolithic template created a random_uuid to stand in for AWS::StackId and sliced one
# segment back out of it to name the key pair; key_name_prefix is the provider's own way of getting a unique
# name, and nothing else read the uuid. The stack_name variable that fed it went with it - its only other use
# was the cfn-signal call, which had no stack to signal.
