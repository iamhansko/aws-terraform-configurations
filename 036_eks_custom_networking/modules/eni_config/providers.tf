terraform {
  required_providers {
    # alekc/kubectl rather than hashicorp/kubernetes. These are CRD instances whose
    # CRD is installed by the vpc-cni addon in the same apply, and
    # kubernetes_manifest needs to resolve a resource schema from the API server
    # during plan - which it cannot do for a type that does not exist yet
    # (rules.md E-2).
    kubectl = { source = "alekc/kubectl" }
  }
}
