terraform {
  required_providers {
    # kubectl only: these two objects are CRDs the Karpenter chart installs, and this module
    # owns nothing in AWS.
    #
    # alekc/kubectl rather than hashicorp/kubernetes, because the cluster and the CRDs
    # themselves are created by the same terraform apply - hashicorp/kubernetes would need
    # both to exist at plan time to resolve the schema (rules.md E-2/E-3).
    kubectl = { source = "alekc/kubectl" }
  }
}
