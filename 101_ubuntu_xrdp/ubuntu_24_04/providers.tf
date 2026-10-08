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
# It used random_uuid to stand in for AWS::StackId and then sliced a segment out
# of that uuid to build a unique key pair name. aws_key_pair has key_name_prefix
# for exactly that, so the uuid - and the provider it needed - are gone. The
# stack_name variable the template carried for the same reason is gone too: the
# only thing that read it was the cfn-signal call, which could never have worked
# because there is no CloudFormation stack here.
#
# tls is still here and does real work: it generates the SSH key pair whose
# private half the key_pair module writes to Parameter Store.
