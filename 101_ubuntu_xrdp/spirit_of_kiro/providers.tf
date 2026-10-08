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
# No random provider, which the _monolithic template required. It used
# random_uuid to stand in for AWS::StackId only so it could slice a unique key
# pair name out of it; aws_key_pair has key_name_prefix for that. The stack_name
# variable went with it - the only thing that read it was a cfn-signal call that
# could never work, because there is no CloudFormation stack here.
#
# tls generates the SSH key pair whose private half goes to Parameter Store.
