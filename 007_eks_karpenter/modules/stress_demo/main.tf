# The workload half of the Karpenter demo, equivalent to 02_stress_pod.yaml in
# https://github.com/AWS-Skills/eks-deepdive/tree/main/karpenter, which the
# _monolithic bootstrap left to a human running "kubectl apply -f" on the
# bastion. Declared as a resource instead, so terraform plan shows drift and
# terraform destroy removes it (rules.md E-1).
#
# Nothing here does any work: the pods run pause and hold a CPU request. That
# request is what Karpenter's scheduling simulation reads, so raising the replica
# count creates pods no existing node can fit and Karpenter answers with new
# nodes. Lowering it again leaves nodes empty, and consolidation removes them.
#
# Uses alekc/kubectl rather than hashicorp/kubernetes because this module is
# applied in the same terraform apply as the cluster whose outputs configure the
# provider (rules.md E-2).
resource "kubectl_manifest" "stress_deployment" {
  yaml_body = yamlencode({
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = var.name
      namespace = var.namespace
      labels    = { app = var.name }
    }
    spec = {
      replicas = var.replica_count
      selector = {
        matchLabels = { app = var.name }
      }
      template = {
        metadata = {
          labels = { app = var.name }
        }
        spec = {
          terminationGracePeriodSeconds = var.termination_grace_period_seconds
          # Pins the pods to nodes Karpenter provisioned. Without this they
          # would happily fit on the managed node group that hosts the
          # controller, and the demo would show no new capacity at all.
          nodeSelector = var.node_selector
          containers = [{
            name  = var.name
            image = var.image
            resources = {
              requests = {
                cpu = var.cpu_request
              }
            }
          }]
        }
      }
    }
  })

  wait_for_rollout = var.wait_for_rollout

  # The demo is run with "kubectl scale", which changes spec.replicas in the
  # cluster. Without this, the next plan would report that drift and the next
  # apply would snap the Deployment back to replica_count, undoing the scale-up
  # mid-demo.
  ignore_fields = ["spec.replicas"]
}
