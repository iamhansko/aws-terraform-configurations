terraform {
  required_providers {
    # helm only, no aws: this module installs a chart and owns no AWS resource.
    # hashicorp/helm is kept rather than worked around, because the helm provider does not need
    # the cluster at plan time the way hashicorp/kubernetes does (rules.md E-2).
    helm = { source = "hashicorp/helm" }
  }
}
