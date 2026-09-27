terraform {
  required_providers {
    # helm for the chart; alekc/kubectl for the Secret and Ingress, which are raw
    # manifests rather than chart output. alekc/kubectl rather than
    # hashicorp/kubernetes because this module is applied alongside the cluster it
    # targets, and kubernetes_manifest needs the API server at plan time
    # (rules.md E-2). http for the upstream values file.
    helm    = { source = "hashicorp/helm" }
    kubectl = { source = "alekc/kubectl" }
    http    = { source = "hashicorp/http" }
  }
}
