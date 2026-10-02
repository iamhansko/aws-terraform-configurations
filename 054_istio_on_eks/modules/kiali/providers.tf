terraform {
  required_providers {
    # helm for the operator, kubectl for the Ingress in front of the server the
    # operator creates.
    helm = { source = "hashicorp/helm" }
    # alekc/kubectl rather than hashicorp/kubernetes, because the cluster this Ingress
    # goes into is created by the same terraform apply. hashicorp/kubernetes is
    # configured during plan, when the cluster endpoint is still unknown, and fails
    # with "Failed to construct REST client ... no client config" (rules.md E-2).
    kubectl = { source = "alekc/kubectl" }
  }
}
