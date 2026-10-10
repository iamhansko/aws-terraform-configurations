terraform {
  required_version = ">= 1.9"
  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 6.0" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
    tls    = { source = "hashicorp/tls", version = "~> 4.0" }
  }
}
provider "aws" {
  region = var.aws_region
}
# tls generates the SSH key pair whose private half the key_pair module writes to Parameter Store.
#
# random stays, which the _monolithic template also required but used for something else. There it was
# random_uuid standing in for AWS::StackId, assembled into a CloudFormation-shaped ARN string so that one
# segment could be sliced back out of it to make the key pair name unique. aws_key_pair has key_name_prefix
# for exactly that, so the uuid, local.stack_id and the stack_name variable are all gone - nothing else read
# them.
#
# What random does here instead is generate the database master password. The template had that as a
# variable with default = "dbpassword"; see modules/rds_mysql for why the default is what had to go rather
# than the variable.
#
# No kubectl or helm provider, and nothing here needs one - rules.md E-2 and E-9 are about clusters whose API
# server Terraform has to reach during the same apply. The equivalent problem does exist in this project and
# is worth naming because the shape is familiar: an image has to exist inside a registry before a resource
# referencing it can work. The answer is the same as rules.md E-9's - have an instance inside the VPC do the
# work and have SSM associations report when it is done - and main.tf is where that happens.
