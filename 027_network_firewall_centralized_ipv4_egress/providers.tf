terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
    # Generates the SSH key pair whose private half the key_pair module writes to Parameter Store.
    tls = { source = "hashicorp/tls", version = "~> 4.0" }
  }
}
provider "aws" {
  region = var.aws_region
}
# Two providers the _monolithic template required are gone, and both deletions are worth recording because
# each took a chunk of the configuration with it.
#
# archive
# -------
# It built a zip from lambda_src/custom_resource_lambda_function/index.py for a Lambda function whose only
# job was to call ec2:DescribeTransitGateways and return the transit gateway's default association route
# table id - a value CloudFormation does not expose and the AWS provider does, as
# aws_ec2_transit_gateway.association_default_route_table_id. The function, its IAM role, the inline policy
# granting ec2:* on "*", the role policy attachment, the aws_lambda_invocation that called it and the
# archive_file that packaged it are all deleted. modules/transit_gateway/main.tf carries the full
# reasoning, including the four independent reasons the converted version could never have run.
#
# lambda_src/ is still on disk and is referenced by nothing. It is left there on purpose: it is the
# evidence for that note, and a reader comparing this configuration against _monolithic/ will look for it.
# Nothing in this project reads it, nothing builds it, and deleting it would change nothing.
#
# random
# ------
# It generated a uuid to stand in for AWS::StackId, so that a segment of that uuid could be sliced out to
# build a unique key pair name. aws_key_pair has key_name_prefix for exactly that. The stack_name variable
# went with it: the only other things that read it were the Lambda function's name and the cfn-signal call
# at the end of the user data, and that call could never have worked - there is no CloudFormation stack
# here, the conversion itself notes the CreationPolicy it signalled is not reproduced, and
# aws-cfn-bootstrap is not installed on Amazon Linux 2023.
#
# data.aws_caller_identity and data.aws_partition went the same way. They existed only to assemble the fake
# stack ARN that the key name was sliced out of.
