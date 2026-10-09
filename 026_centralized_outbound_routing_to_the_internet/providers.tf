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
# Two providers fewer than the _monolithic file declared, and both removals are consequences of
# deleting things rather than of replacing them.
#
# archive is gone because the Lambda function is gone. The _monolithic template carried a
# CloudFormation custom resource whose entire job was to look up the transit gateway's default
# association route table id, and the AWS provider exposes that id as an attribute of the gateway
# itself - aws_ec2_transit_gateway.association_default_route_table_id. See
# modules/transit_gateway/main.tf for the attribute and lambda_src/custom_resource_lambda_function/index.py
# for the four independent reasons the converted function could not have returned it anyway.
#
# random is gone because nothing needs a generated suffix any more. The _monolithic template used
# random_uuid to stand in for AWS::StackId and then derived the key pair's name from it by splitting
# that synthetic ARN twice - key-${element(split("-", element(split("/", local.stack_id), 2)), 3)}.
# The name is a variable now (see modules/key_pair), which costs the ability to apply this root twice
# into one account and region: the second apply fails with InvalidKeyPair.Duplicate. That is the same
# trade the rest of this repository makes for key pairs, and it is visible in a plan rather than
# hidden in string surgery.
#
# tls stays: CloudFormation's AWS::EC2::KeyPair generates key material itself and Terraform has no
# equivalent, so modules/key_pair reproduces it with tls_private_key.
