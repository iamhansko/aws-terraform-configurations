terraform {
  required_version = ">= 1.9"
  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 6.0" }
    archive = { source = "hashicorp/archive", version = "~> 2.4" }
    random  = { source = "hashicorp/random", version = "~> 3.6" }
    http    = { source = "hashicorp/http", version = "~> 3.4" }
  }
}
provider "aws" {
  region = var.aws_region
}
# Providers compared with the _monolithic template:
#
#   tls     - gone. It generated an SSH key pair that nothing used: the managed instances are launched by ECS
#             from its own launch template, which takes no key pair, and there is no other instance here. The
#             key and the Parameter Store copy of its private half are not reproduced.
#   random  - kept, for a different job. It used to stand in for AWS::StackId so a uuid slice could make
#             names unique; name_prefix does that now. What it does here is generate the Shlink API key,
#             which a Lambda custom resource used to produce.
#   archive - kept, for the one Lambda function left: the destroy-time drain of the managed instances.
