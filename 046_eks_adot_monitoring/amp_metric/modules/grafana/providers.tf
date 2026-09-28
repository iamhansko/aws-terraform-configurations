terraform {
  required_providers {
    # Four, because this is one component whose halves all reference each other: the IRSA
    # role Grafana assumes to query AMP, the operator that installs Grafana, the Secret
    # holding the admin credential, and the two custom resources the operator acts on
    # (rules.md C-2).
    aws     = { source = "hashicorp/aws" }
    helm    = { source = "hashicorp/helm" }
    kubectl = { source = "alekc/kubectl" }
    random  = { source = "hashicorp/random" }
  }
}
