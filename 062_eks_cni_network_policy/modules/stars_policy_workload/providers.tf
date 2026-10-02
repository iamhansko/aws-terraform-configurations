terraform {
  required_providers {
    # kubectl only, no aws: this module owns Kubernetes objects and nothing in AWS.
    #
    # alekc/kubectl rather than hashicorp/kubernetes, because the cluster these
    # objects go into is created by the same terraform apply. hashicorp/kubernetes
    # is configured during plan, when the cluster endpoint is still unknown, and
    # fails with "Failed to construct REST client ... no client config"
    # (rules.md E-2).
    kubectl = { source = "alekc/kubectl" }
  }
}
