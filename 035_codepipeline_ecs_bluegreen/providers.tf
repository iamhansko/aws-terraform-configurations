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
# One provider, one account, one region. rules.md I-1 and I-3 are about crossing an account or a
# region boundary and neither is crossed here, so there are no aliases and no assume_role.
#
# No kubectl and no helm provider either. rules.md E-1 and E-2 are about a cluster whose API server
# Terraform has to reach inside the same apply, and there is no Kubernetes cluster in this project -
# ECS is an AWS API, so every object in it is an ordinary aws provider resource.
#
# The shape of problem E-9 describes does exist here, though, and it is worth naming because the
# answer is the same: a container image has to be inside the registry before a task definition that
# references it can start a task, and no attribute of any Terraform resource says whether it is.
# E-9's answer is to have an instance inside the VPC do the work and an SSM association report when
# it is done, and that is what aws_ssm_association.image_pushed in main.tf is.
#
# tls stays and does real work: it generates the SSH key pair whose private half the key_pair module
# writes to Parameter Store as a SecureString.
#
# random is gone, and that is a deliberate removal rather than an omission.
#
# The _monolithic template needed it to stand in for AWS::StackId. It created a random_uuid,
# assembled a string shaped like a CloudFormation stack ARN around it, and then sliced one segment
# back out of that string to get a unique suffix:
#
#   stack_suffix = element(split("-", element(split("/", local.stack_id), 2)), 3)
#
# which it appended to four IAM role names, two instance profile names and the key pair name. The
# property it was buying is real - all of those namespaces are account-wide, so a fixed name
# collides with a second copy of this project and the collision is an EntityAlreadyExists at apply -
# but name_prefix and key_name_prefix are the provider's own way of getting it. So the uuid, the
# synthetic stack ARN and the stack_name variable that fed it are all gone, and nothing else read
# local.stack_id.
#
# var.stack_name is replaced by var.project_name. Same job of prefixing the names CloudFormation
# used to supply, without claiming to be a stack name: the only thing that used it as one was the
# cfn-signal call at the end of the bastion userdata, which could not have worked - there is no
# CloudFormation stack for it to signal and aws-cfn-bootstrap is not on Amazon Linux 2023, so the
# line ends in "No such file or directory". See modules/bastion_ec2 for what replaces it.
