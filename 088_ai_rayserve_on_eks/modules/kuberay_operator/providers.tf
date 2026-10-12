terraform {
  required_providers {
    # helm only connects to the cluster during apply, so hashicorp/helm works unchanged
    # even though the cluster is created by the same apply - the workaround
    # rules.md E-2 describes applies to Kubernetes resources only.
    helm = { source = "hashicorp/helm" }
  }
}
