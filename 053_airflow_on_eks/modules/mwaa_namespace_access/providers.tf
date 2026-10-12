terraform {
  required_providers {
    # alekc/kubectl, not hashicorp/kubernetes, which the blueprint used for these three objects
    # (kubernetes_namespace_v1, kubernetes_role_v1, kubernetes_role_binding_v1). The cluster they go
    # into is created by the same terraform apply here, and the typed provider cannot be configured
    # at plan time against an endpoint that does not exist yet (rules.md E-2).
    kubectl = { source = "alekc/kubectl" }
  }
}
