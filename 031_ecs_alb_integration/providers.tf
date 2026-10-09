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
# It declared random_uuid to stand in for AWS::StackId and then sliced one segment back out of it to make
# two names unique: the key pair ("key-<segment>") and the instance profile ("Ec2AdminProfile-<segment>").
# Both of those namespaces are account-wide, so the property it bought is real - two copies of this project
# in one account do not collide on either. key_name_prefix and name_prefix are the provider's own way of
# getting it, and using them drops the uuid, the local that parsed it and the provider itself.
#
# tls stays: it generates the key pair whose private half the key_pair module writes to Parameter Store.
