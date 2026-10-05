terraform {
  required_providers {
    # Both: this module creates the pods and the IAM role the sidecar in them assumes. They
    # are kept together because the role's trust policy and the pod's service account have to name
    # the same thing (rules.md C-2).
    aws     = { source = "hashicorp/aws" }
    kubectl = { source = "alekc/kubectl" }
  }
}
