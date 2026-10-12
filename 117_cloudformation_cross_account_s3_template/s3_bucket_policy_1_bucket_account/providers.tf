terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}
# No profile and no assume_role: which account this applies to is the caller's credential chain, and a
# precondition in main.tf refuses the wrong one (rules.md I-1). The stack account is a separate root with its
# own state, applied with that account's credentials.
provider "aws" {
  region = var.aws_region
}
# No archive or random provider, which the _monolithic template required.
#
# archive_file zipped a Lambda function whose only job was to put the template into the bucket with
# put_object - as a CloudFormation custom resource, through cfnresponse. aws_s3_object does that directly.
# The function could not have worked under aws_lambda_invocation in any case: it read event["RequestType"]
# and event["ResourceProperties"], which only CloudFormation sends, and imported cfnresponse, a module that
# exists only in CloudFormation's inline-code runtime.
#
# random_uuid stood in for AWS::StackId to make the bucket name unique; bucket_prefix does that.
