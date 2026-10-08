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
# The provider set is the same three the _monolithic template declared, but two
# of them do a different job here and one dependency it carried is gone.
#
# random is still required, for the workshop password. It is no longer required
# for a uuid: the template generated random_uuid to stand in for AWS::StackId,
# built local.stack_id out of it with data.aws_partition and
# data.aws_caller_identity, and then read one slice of that string to make a
# unique key pair name. aws_key_pair has key_name_prefix for exactly that, so
# the uuid, the local and both data sources are dropped - nothing else read any
# of them.
#
# tls generates the key pair whose private half the key_pair module writes to
# Parameter Store. On Windows that is not a convenience the way an SSH key is on
# Linux: EC2 encrypts the Administrator password with this key pair at launch,
# and losing the private half means losing Administrator.
#
# archive is gone entirely. The template needed it for the SecretPlaintextLambda
# custom resource whose only job was reading the generated password back out of
# Secrets Manager, because CloudFormation cannot resolve a secret's value into
# an output. Terraform has no such limitation; the app_secret module explains
# what that Lambda was and why reinstating it would not work.
#
# There is no kubernetes or helm provider to think about here, so rules.md E-2
# and E-9 do not apply - this project has no cluster.
