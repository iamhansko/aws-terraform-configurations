terraform {
  required_providers {
    # hashicorp/helm needs no workaround here: unlike hashicorp/kubernetes it does
    # not contact the cluster at plan time, so this release and the cluster it
    # targets can be created in a single apply (rules.md E-2).
    helm = { source = "hashicorp/helm" }
  }
}
