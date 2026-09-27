terraform {
  required_providers {
    # helm for the operator, alekc/kubectl for the Grafana and GrafanaDatasource
    # custom resources. alekc/kubectl rather than hashicorp/kubernetes because this
    # module is applied alongside the cluster it targets, and kubernetes_manifest
    # needs the API server at plan time to resolve a resource schema - which for a
    # CRD the operator has not installed yet it could not do anyway (rules.md E-2).
    helm    = { source = "hashicorp/helm" }
    kubectl = { source = "alekc/kubectl" }
  }
}
