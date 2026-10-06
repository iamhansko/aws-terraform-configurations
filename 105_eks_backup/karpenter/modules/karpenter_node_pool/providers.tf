terraform {
  required_providers {
    # alekc/kubectl, not hashicorp/kubernetes: these are custom resources whose CRDs are
    # installed by a Helm release in the same terraform apply, so a typed provider would
    # need the schema at plan time and fail (rules.md E-2/E-3).
    kubectl = { source = "alekc/kubectl" }
  }
}
