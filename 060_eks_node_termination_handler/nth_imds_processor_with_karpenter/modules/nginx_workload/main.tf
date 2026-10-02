# The workload the node termination demo drains.
#
# Its whole job is to be visibly disrupted: enough replicas that they span every node, so an
# interruption sent to one instance shows pods moving rather than a single pod restarting.
#
# The _monolithic template wrote this Deployment as a single-quoted shell string inside an SSM
# Association and applied it with kubectl, so it was not in state - no diff in plan, nothing
# removed on destroy, and a YAML indentation error would have surfaced only in the
# association's output (rules.md E-1/E-2).
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
        spec = merge(
          # Omitted entirely when no selector was given, which is the case for a node group
          # the handler covers directly - there is nothing to pin to and every node is a
          # valid home (rules.md B-4).
          length(var.node_selector) > 0 ? { nodeSelector = var.node_selector } : {},
          {
            # Spreads the replicas across nodes instead of letting the scheduler stack them.
            # Without this the scheduler is free to place most of a 12-replica Deployment on
            # one node, and interrupting a different node then shows nothing at all - the
            # demo would look like the handler had done its job when it simply had no pods
            # to drain.
            topologySpreadConstraints = [{
              maxSkew           = var.max_skew
              topologyKey       = "kubernetes.io/hostname"
              whenUnsatisfiable = "ScheduleAnyway"
              labelSelector = {
                matchLabels = { app = var.name }
              }
            }]
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
          },
        )
      }
    }
  })
}
# Keeps a drain from evicting every replica at once.
#
# The _monolithic template had no budget, so a cordon-and-drain could take the whole
# Deployment down at once and the demo showed it going away and coming back rather than
# surviving the disruption. With one, the handler has to evict in stages - which is the
# behaviour worth watching, and also the thing a budget set too tightly can deadlock: a
# budget that cannot be satisfied blocks the drain until the instance is reclaimed anyway,
# which is exactly the failure a two-minute notice does not leave time to recover from.
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
  # Deployment (rules.md D-1).
  depends_on = [kubectl_manifest.deployment]
}
