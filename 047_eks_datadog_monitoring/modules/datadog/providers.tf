terraform {
  required_providers {
    # helm for the operator's chart, kubectl for the Secret and the DatadogAgent custom
    # resource. No aws: this module owns nothing in AWS.
    #
    # alekc/kubectl rather than hashicorp/kubernetes, because these objects go into a
    # cluster the same apply creates. hashicorp/kubernetes is configured during plan, when
    # the cluster endpoint is still unknown, and fails with "Failed to construct REST
    # client ... no client config" (rules.md E-2).
    helm    = { source = "hashicorp/helm" }
    kubectl = { source = "alekc/kubectl" }
  }
}
