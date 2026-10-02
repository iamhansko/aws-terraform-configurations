terraform {
  required_providers {
    # Both, because this module is one component with two halves: the IAM role the
    # operator assumes, and the chart that annotates its service account with that
    # role's ARN. Splitting them would mean passing an ARN across a module boundary for
    # no gain, since neither half is useful without the other (rules.md C-2).
    aws  = { source = "hashicorp/aws" }
    helm = { source = "hashicorp/helm" }
  }
}
