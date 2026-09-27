terraform {
  required_providers {
    # helm only: both releases are charts, and the ClusterPolicy objects come from
    # the policies chart rather than from raw manifests here. hashicorp/helm needs no
    # workaround for a cluster created in the same apply (rules.md E-2).
    helm = { source = "hashicorp/helm" }
  }
}
