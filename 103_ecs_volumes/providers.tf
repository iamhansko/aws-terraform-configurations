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
# It used random_uuid to stand in for AWS::StackId, built a local.stack_id string shaped like a
# CloudFormation stack ARN out of it, and then sliced one segment back out of that string to get a unique
# key pair name. aws_key_pair has key_name_prefix for exactly that, so the uuid and the provider it needed
# are both gone, along with local.stack_id - nothing else read it.
#
# The stack_name variable it carried is replaced by project_name. Same job - prefixing the generated names
# CloudFormation used to supply - but it is no longer pretending to be a stack name: the only thing that
# used it as one was the cfn-signal call in the instance userdata, which could never have worked because
# there is no CloudFormation stack here and aws-cfn-bootstrap is not installed on Amazon Linux 2023.
#
# tls stays and does real work: it generates the SSH key pair whose private half the key_pair module
# writes to Parameter Store.
#
# No kubectl or helm provider, and nothing here needs one - rules.md E-2 and E-9 are about clusters whose
# API server Terraform has to talk to during the same apply. The equivalent problem does exist in this
# project, though, and it is worth naming because the shape is familiar: an image that has to exist inside
# a registry before a resource that references it can work. The answer here is the same as rules.md E-9's
# - have an instance inside the VPC do the work and have an SSM association report when it is done - and
# main.tf is where that happens.
