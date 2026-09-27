terraform {
  required_providers {
    # helm only: this module installs a chart and owns no AWS resource
    # (rules.md E-2).
    helm = { source = "hashicorp/helm" }
  }
}
