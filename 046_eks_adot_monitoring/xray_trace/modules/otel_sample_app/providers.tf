terraform {
  required_providers {
    # Both, because the IAM role and the Kubernetes objects reference each other: the
    # service account is annotated with the role's ARN, and the role's trust policy names
    # that service account. Neither half is useful alone (rules.md C-2).
    aws = { source = "hashicorp/aws" }
    # alekc/kubectl rather than hashicorp/kubernetes, because the cluster these objects go
    # into is created by the same terraform apply. hashicorp/kubernetes is configured
    # during plan, when the cluster endpoint is still unknown, and fails with
    # "Failed to construct REST client ... no client config" (rules.md E-2).
    kubectl = { source = "alekc/kubectl" }
  }
}
