terraform {
  required_providers {
    # PodMonitor is a custom resource whose CRD the kube-prometheus-stack release installs in the same
    # terraform apply (rules.md E-2/E-3).
    kubectl = { source = "alekc/kubectl" }
  }
}
