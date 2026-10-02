terraform {
  required_providers {
    # aws only: this module owns an EKS addon and the IAM role it runs as. Nothing here
    # talks to the cluster's API server, so no kubectl or helm provider is needed - and
    # that is also why this module is outside the reach of rules.md D-4.
    aws = { source = "hashicorp/aws" }
  }
}
