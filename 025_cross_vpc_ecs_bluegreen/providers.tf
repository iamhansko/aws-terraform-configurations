terraform {
  required_version = ">= 1.9"
  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 6.0" }
    tls     = { source = "hashicorp/tls", version = "~> 4.0" }
    archive = { source = "hashicorp/archive", version = "~> 2.4" }
  }
}
provider "aws" {
  region = var.aws_region
}
# One provider, no aliases, and that is worth saying because the project's name invites the
# opposite reading. rules.md I-1 and I-3 are about crossing an account or a region boundary: a
# second account needs its own root module because it needs different credentials, and a second
# region needs a provider alias because the region is an argument of the provider. Neither applies
# here. This is cross-VPC inside one account and one region, so both VPCs, the peering connection
# and everything in them are built by the same provider - and a peering connection between two VPCs
# of one provider is the only reason it can be auto-accepted in a single apply.
#
# No random provider, which the _monolithic template required.
#
# It used random_uuid to stand in for AWS::StackId, assembled a string shaped like a CloudFormation
# stack ARN out of it, and then sliced one segment back out of that string to get a unique suffix:
#
#   stack_suffix = element(split("-", element(split("/", local.stack_id), 2)), 3)
#
# which it appended to five IAM role names, the instance profile names and the key pair name. The
# property it bought is real - all of those names are account-wide, so a fixed one collides with a
# second copy of this project - but name_prefix on each of those resources is the provider's own
# way of getting it. So the uuid, the synthetic stack ARN, the stack_name variable that fed it and
# the provider itself are all gone. Nothing else read local.stack_id.
#
# The stack_name variable is replaced by project_name. Same job, prefixing the names
# CloudFormation used to supply, without pretending to be a stack name: the only thing that used
# it as one was the cfn-signal call at the end of the workbench userdata, which could not have
# worked - there is no CloudFormation stack here, and aws-cfn-bootstrap is not installed on
# Amazon Linux 2023. The conversion's own comment notes that the CreationPolicy the signal was
# answering is not reproduced.
#
# tls stays and does real work: it generates the SSH key pair whose private half the key_pair
# module writes to Parameter Store.
#
# archive zips the seed artefact each pipeline reads on the execution CodePipeline starts at
# creation. Without it that execution finds an empty source bucket and fails - see
# modules/app_stack, data.archive_file.seed_artifact.
#
# No kubectl or helm provider, and nothing here needs one - rules.md E-2 and E-9 are about a
# cluster whose API server Terraform has to reach during the same apply. The shape of problem they
# solve does exist in this project, though, and it is worth naming because it is the same one: a
# container image has to be inside a registry before a task definition that references it can
# work, and a database schema has to exist before the application can answer. The answer here is
# E-9's - have an instance inside the VPC do the work and have an SSM association report when it
# is done - and main.tf is where that happens.
