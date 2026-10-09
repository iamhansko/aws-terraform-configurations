terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
    # The function is deployed from source in this repository, so the zip is built during the run rather than
    # uploaded beforehand. archive_file does it at plan time, which makes a change to index.py a plan diff.
    archive = { source = "hashicorp/archive", version = "~> 2.4" }
    # Generates the SSH key pair whose private half the key_pair module writes to Parameter Store.
    tls = { source = "hashicorp/tls", version = "~> 4.0" }
  }
}
provider "aws" {
  region = var.aws_region
}
# No random provider, which the _monolithic conversion required.
#
# It used random_uuid to stand in for AWS::StackId, then sliced a segment out of that uuid to build a unique
# key pair name. aws_key_pair has key_name_prefix for exactly that, so the uuid and the provider it needed are
# both gone. The stack_name variable went with them: the only things that read it were the two cfn-signal
# calls at the end of the user data scripts, which could never have worked - there is no CloudFormation stack
# here, the conversion itself notes the CreationPolicy they signalled is not reproduced, and
# aws-cfn-bootstrap is not installed on Amazon Linux 2023.
