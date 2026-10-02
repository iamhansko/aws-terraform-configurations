# A workload pinned to one Karpenter node pool, so that pool has nodes for an experiment to
# take away.
#
# Nothing about a NodePool provisions anything on its own - Karpenter provisions for pending
# pods it can satisfy, so without this the pool exists and the cluster has no Karpenter nodes
# at all. The FIS experiments would then resolve to no targets, which with
# empty_target_resolution_mode = fail is at least a visible failure.
#
# The _monolithic template wrote this Deployment as a single-quoted shell string inside an SSM
# Association and applied it with kubectl, so it was not in state: no diff in plan, nothing
# removed on destroy (rules.md E-1/E-2).
resource "kubectl_manifest" "deployment" {
  yaml_body = yamlencode({
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = var.name
      namespace = var.namespace
      labels    = { app = var.name }
    }
    spec = {
      replicas = var.replicas
      selector = {
        matchLabels = { app = var.name }
      }
      template = {
        metadata = {
          labels = { app = var.name }
        }
        spec = {
          # The labels the node pool writes onto its nodes. This is what keeps these pods off
          # the managed node group and is the only reason Karpenter provisions at all
          # (rules.md B-5).
          nodeSelector = var.node_selector
          containers = [{
            name  = var.name
            image = var.image
            ports = [{
              name          = "http"
              containerPort = 80
            }]
            resources = {
              requests = {
                cpu    = var.cpu_request
                memory = var.memory_request
              }
            }
          }]
        }
      }
    }
  })
}
# Keeps a drain from evicting every replica at once.
#
# The _monolithic template had no budget, so an interruption experiment shows the workload
# going away and coming back rather than staying up through the disruption. With one, Karpenter
# and the termination handler have to evict in stages - which is the behaviour the experiment is
# meant to demonstrate, and also the thing a budget set too tightly can deadlock: a budget that
# cannot be satisfied blocks the drain until the node is reclaimed anyway.
resource "kubectl_manifest" "pod_disruption_budget" {
  count = var.min_available == null ? 0 : 1

  yaml_body = yamlencode({
    apiVersion = "policy/v1"
    kind       = "PodDisruptionBudget"
    metadata = {
      name      = var.name
      namespace = var.namespace
    }
    spec = {
      minAvailable = var.min_available
      selector = {
        matchLabels = { app = var.name }
      }
    }
  })

  # The selector is a literal label rather than a reference, so nothing orders this after the
  # Deployment (rules.md D-1). A budget created first would briefly guard a workload that does
  # not exist, which blocks nothing but reads oddly in the API server's events.
  depends_on = [kubectl_manifest.deployment]
}
