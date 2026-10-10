terraform {
  required_version = ">= 1.9"
  required_providers {
    aws   = { source = "hashicorp/aws", version = "~> 6.0" }
    awscc = { source = "hashicorp/awscc", version = "~> 1.0" }
    tls   = { source = "hashicorp/tls", version = "~> 4.0" }
    # Zips the handler of modules/s3_object_waiter, the function that holds the Lambda functions and the
    # GameLift build until the workbench's uploads are in S3.
    archive = { source = "hashicorp/archive", version = "~> 2.4" }
  }
}
provider "aws" {
  region = var.aws_region
}
# A second AWS provider, which no other root in this repository has, for exactly two resources: the FlexMatch
# matchmaking rule set and matchmaking configuration in modules/gamelift_matchmaking. hashicorp/aws has no
# matchmaking resources at all - that is why the _monolithic template carried both as NOT CONVERTED - and
# hashicorp/awscc exposes them through the Cloud Control API. Without them this project's subject is missing:
# game-match-request starts matchmaking against a configuration that does not exist.
#
# Same region variable as the aws provider, so the two cannot be pointed at different regions by configuration.
# With it null each provider follows its own chain; the check block in main.tf reports a mismatch.
provider "awscc" {
  region = var.aws_region
}
# tls generates the key pair whose private half the key_pair module writes to Parameter Store. The random
# provider the _monolithic template used is gone: every name it derived from its random_uuid now comes from a
# provider-side prefix (key_name_prefix, bucket_prefix, name_prefix).
