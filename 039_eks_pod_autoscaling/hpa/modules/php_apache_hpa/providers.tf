terraform {
  required_providers {
    # alekc/kubectl rather than hashicorp/kubernetes, because this module is applied
    # alongside the cluster whose outputs configure the provider, and the typed
    # resources need the API server during plan (rules.md E-2).
    kubectl = { source = "alekc/kubectl" }
  }
}
