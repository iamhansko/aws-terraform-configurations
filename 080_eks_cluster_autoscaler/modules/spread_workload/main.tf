# A Deployment whose only job is to want more capacity than the cluster has.
#
# The _monolithic template wrote two of these into files on the bastion -
# manifests/zone.yaml and manifests/node.yaml - and never applied them. So an apply produced
# a cluster with an autoscaler and nothing to autoscale, and the demo only started once
# someone read the SSM Association's shell script closely enough to find the files and run
# kubectl by hand. Here they are Terraform resources: in state, visible in plan, and driven
# by a replica count that can be changed with terraform apply (rules.md E-1/E-2).
#
# The two instances differ in exactly one field, topologyKey, and that difference is the
# lesson. Spreading on topology.kubernetes.io/zone balances across availability zones, so
# three nodes in one zone satisfy it no better than one does. Spreading on
# kubernetes.io/hostname balances across nodes, so it keeps pushing work onto new ones. On the
# same cluster, with the same replica count, they ask the autoscaler for different things.
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
          topologySpreadConstraints = [{
            maxSkew     = var.max_skew
            topologyKey = var.topology_key
            # ScheduleAnyway, so an unsatisfiable spread never leaves a pod Pending. That
            # matters more here than anywhere else: the autoscaler reacts to Pending pods, and
            # a pod that is Pending for a reason no new node can fix makes it scale up to the
            # node group's maximum and stop, with nothing scheduled and no error.
            whenUnsatisfiable = var.when_unsatisfiable
            labelSelector = {
              matchLabels = { app = var.name }
            }
          }]
          containers = [{
            name  = var.name
            image = var.image
            # The requests are the point. The scheduler places pods by request, and the
            # autoscaler decides both to add a node (a pod's request fits nowhere) and to
            # remove one (the sum of requests on it is below the utilization threshold) from
            # these numbers alone. Actual CPU use never enters into it - which is why this
            # demo works with containers that do nothing at all.
            resources = {
              requests = {
                cpu    = var.cpu_request
                memory = var.memory_request
              }
              limits = {
                cpu    = var.cpu_limit
                memory = var.memory_limit
              }
            }
          }]
        }
      }
    }
  })
}
