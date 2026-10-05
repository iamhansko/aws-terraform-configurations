# The workload the node group update has to drain.
#
# Nothing here serves traffic to anyone - the point is that these pods are the reason a
# node cannot simply be terminated. Three things decide what the update looks like, and
# all three live in this module: how many pods there are, how long a replacement takes to
# turn Ready, and how many may be unavailable at once.
#
# The _monolithic template wrote both objects as a single-quoted shell string inside the
# instance's user data and applied them with kubectl, so they were not in state: no diff
# in plan, nothing removed on destroy, and a YAML indentation error would have surfaced
# only in the cloud-init log. Worse, that kubectl apply sat after an "exec bash" line,
# which replaces the shell and discards everything after it - so on a real boot the
# manifests were never applied at all and the cluster had no budget to demonstrate
# (rules.md E-1/E-2).
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
          # Steers one replica onto each node. Without it the scheduler may stack all
          # three onto a single node, and then two of the three node replacements drain
          # nothing - the update finishes fast and the budget looks like it did nothing.
          # ScheduleAnyway rather than DoNotSchedule: during the update the old nodes are
          # cordoned, so a hard constraint could leave an evicted pod Pending and turn a
          # delay into a deadlock.
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
              containerPort = var.container_port
            }]
            # The clock the whole demo runs on. An evicted pod's replacement counts
            # against the budget until it turns Ready, so this delay is what keeps the
            # next eviction waiting - it is why a three-node update takes minutes rather
            # than seconds.
            readinessProbe = {
              httpGet = {
                path = "/"
                port = var.container_port
              }
              initialDelaySeconds = var.readiness_initial_delay_seconds
              periodSeconds       = var.readiness_period_seconds
            }
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
# What makes the node group update wait.
#
# During the upgrade phase EKS cordons a node and drains it through the eviction API,
# which honours this budget. Each node holds one of the three replicas, so evicting it
# uses up the single permitted disruption and the drain of the next node cannot start
# until the replacement pod is Ready. Fifteen minutes is the per-node limit: past that,
# an unforced update fails with PodEvictionFailure.
resource "kubectl_manifest" "pod_disruption_budget" {
  yaml_body = yamlencode({
    apiVersion = "policy/v1"
    kind       = "PodDisruptionBudget"
    metadata = {
      name      = var.name
      namespace = var.namespace
    }
    spec = merge(
      {
        selector = {
          matchLabels = { app = var.name }
        }
      },
      # Exactly one of the two is non-null, enforced by the cross-variable validation on
      # pdb_min_available - the API server rejects a budget naming both (rules.md B-4).
      var.pdb_max_unavailable == null ? {} : { maxUnavailable = var.pdb_max_unavailable },
      var.pdb_min_available == null ? {} : { minAvailable = var.pdb_min_available },
    )
  })

  # The budget selects pods by a literal label rather than by a reference, so nothing
  # else orders it after the Deployment (rules.md D-1). Order matters on the way out too:
  # a budget that outlives its pods reports zero allowed disruptions, which is what a
  # drain during destroy would then be held up by.
  depends_on = [kubectl_manifest.deployment]
}
