terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
    # Generates the SSH key pair whose private half the key_pair module writes to Parameter Store, which is
    # what CloudFormation does for a key pair it creates.
    tls = { source = "hashicorp/tls", version = "~> 4.0" }
  }
}
provider "aws" {
  region = var.aws_region
}
# No random provider, which the conversion in _monolithic/common_rule_set.tf required.
#
# It declared random_uuid to stand in for AWS::StackId, built a fake stack ARN out of the result in a local,
# and then sliced one segment back out of that ARN to make a unique key pair name. aws_key_pair has
# key_name_prefix for exactly that, so the uuid, the provider it needed and the stack_name variable that fed
# the fake ARN are all gone. stack_name had no other reader except the two cfn-signal calls at the end of the
# userdata scripts, which could never have worked: there is no CloudFormation stack here, the conversion's
# own comment notes that the CreationPolicy they signalled is not reproduced, and aws-cfn-bootstrap is not
# installed on Amazon Linux 2023.
#
# No provider aliased to us-east-1 either, and that is a decision rather than an omission. A WAFv2 web ACL
# of CLOUDFRONT scope has to be created through us-east-1 whatever region the rest of the stack is in; this
# one is REGIONAL because it is associated with an Application Load Balancer, which is a regional resource.
# modules/web_application_firewall/variables.tf pins that and explains it.
