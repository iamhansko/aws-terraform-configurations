terraform {
  required_providers {
    # alekc/kubectl, not hashicorp/kubernetes: the cluster these objects go into
    # is created by the same terraform apply, and a typed Kubernetes provider
    # cannot be configured at plan time against an endpoint that does not exist
    # yet (rules.md E-2).
    kubectl = { source = "alekc/kubectl" }
  }
}
