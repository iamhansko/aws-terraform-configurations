terraform {
  required_providers {
    # alekc/kubectl rather than hashicorp/kubernetes, because this module is applied
    # alongside the cluster whose outputs configure the provider, and because the
    # VerticalPodAutoscaler is a custom resource - hashicorp/kubernetes would need
    # kubernetes_manifest, which reads the CRD from the API server during plan
    # (rules.md E-2/E-3).
    kubectl = { source = "alekc/kubectl" }
  }
}
