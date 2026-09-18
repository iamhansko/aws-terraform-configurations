terraform {
  required_providers {
    # Pods and Services are API server objects, so the AWS provider cannot express
    # them. alekc/kubectl rather than hashicorp/kubernetes because this module is
    # applied alongside the cluster it targets (rules.md E-2).
    kubectl = { source = "alekc/kubectl" }
  }
}
