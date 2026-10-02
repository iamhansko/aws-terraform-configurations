terraform {
  required_providers {
    # helm for the chart, kubectl for the Role and RoleBinding that let the repo-server read the
    # Vault Secret. No aws: this module owns nothing in AWS.
    #
    # alekc/kubectl rather than hashicorp/kubernetes, because these objects go into a cluster the
    # same apply creates - hashicorp/kubernetes is configured during plan, when the endpoint is
    # still unknown (rules.md E-2).
    helm    = { source = "hashicorp/helm" }
    kubectl = { source = "alekc/kubectl" }
  }
}
