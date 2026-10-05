terraform {
  required_providers {
    aws = { source = "hashicorp/aws" }
  }
}
# One provider, and no credential beyond the AWS one. The source this module creates lives in the same
# account as the pipeline that reads it, so there is nothing to authenticate to and nothing to authorise by
# hand.
