terraform {
  required_providers {
    aws = { source = "hashicorp/aws" }
    # For the namespace the profile's selector names, which the AWS provider has no
    # way to create - it is an API server object, not an EKS one (rules.md E-2).
    kubectl = { source = "alekc/kubectl" }
  }
}
