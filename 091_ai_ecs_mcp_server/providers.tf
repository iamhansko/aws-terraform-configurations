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
# It generated a uuid to stand in for AWS::StackId, built a string shaped like a CloudFormation stack ARN out of
# it, and sliced one segment back out to name the key pair. aws_key_pair takes a name prefix for exactly that,
# and the launch template and the Auto Scaling group generate their own names from a prefix, so the uuid, the
# stack ARN local and the provider are all gone. The stack_name variable it carried survives as project_name,
# which prefixes the names CloudFormation used to derive from the stack name - the cluster, the capacity
# provider and the cache policy.
#
# tls generates the key pair (modules/key_pair) the workbench and the container instances share.
