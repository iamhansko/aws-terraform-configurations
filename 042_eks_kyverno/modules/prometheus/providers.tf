terraform {
  required_providers {
    # helm only: this module installs a chart and owns no AWS resource. hashicorp/helm
    # needs no workaround for a cluster created in the same apply, unlike
    # hashicorp/kubernetes (rules.md E-2).
    helm = { source = "hashicorp/helm" }
  }
}
