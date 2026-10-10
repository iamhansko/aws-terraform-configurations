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
# It used random_uuid to stand in for AWS::StackId, built a string shaped like a CloudFormation stack ARN
# out of it, and sliced one segment back out of that string to suffix the key pair, the two task roles and
# the log group. The key pair and the roles take name prefixes instead, and the log group is named after
# project_name, so nothing needs a generated suffix.
#
# tls stays and does real work: it generates the SSH key pair whose private half the key_pair module
# writes to Parameter Store.
