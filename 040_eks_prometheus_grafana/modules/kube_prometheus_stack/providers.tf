terraform {
  required_providers {
    # hashicorp/helm is fine here: unlike hashicorp/kubernetes it does not need to
    # reach the cluster at plan time, so this release and the cluster it targets
    # can be created in one apply (rules.md E-2).
    helm = { source = "hashicorp/helm" }
  }
}
