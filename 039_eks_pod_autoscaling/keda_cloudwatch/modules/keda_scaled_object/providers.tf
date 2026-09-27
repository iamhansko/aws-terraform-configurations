terraform {
  required_providers {
    # alekc/kubectl rather than hashicorp/kubernetes. Both objects here are KEDA
    # custom resources, and kubernetes_manifest reads a CRD from the API server during
    # plan - which cannot work when the CRDs arrive with the KEDA release in the same
    # apply (rules.md E-2/E-3).
    kubectl = { source = "alekc/kubectl" }
  }
}
