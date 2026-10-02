terraform {
  required_providers {
    # kubectl only: this module owns a Deployment and nothing in AWS.
    #
    # alekc/kubectl rather than hashicorp/kubernetes, because the cluster this goes into is
    # created by the same terraform apply. hashicorp/kubernetes is configured during plan, when
    # the cluster endpoint is still unknown, and fails with "Failed to construct REST client
    # ... no client config" (rules.md E-2).
    kubectl = { source = "alekc/kubectl" }
  }
}
