terraform {
  required_providers {
    # helm only, no aws and no kubectl: this module installs three charts and owns
    # nothing else.
    #
    # hashicorp/helm needs none of the lazy_load workaround the kubectl provider does.
    # It does not contact the API server while Terraform is building the plan, only
    # during apply, by which time the cluster this root creates exists (rules.md E-2).
    helm = { source = "hashicorp/helm" }
  }
}
