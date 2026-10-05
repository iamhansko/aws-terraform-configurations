# The demo workload: one Deployment with enough replicas to make the node's pod ceiling
# visible.
#
# A declared manifest rather than `kubectl create deployment nginx --image=nginx --replicas=10`
# out of an SSM Association, which is what the _monolithic template ran (rules.md E-1/E-2).
# Two things that command produced are fixed here: the image had no tag, so every pod pulled
# whatever `nginx:latest` was at that moment, and the pods had no resource requests at all - so
# the scheduler placed them by pod count alone, which is exactly the number this variant is
# about but not for a reason anyone chose.
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
      selector = { matchLabels = { app = var.name } }
      template = {
        metadata = { labels = { app = var.name } }
        spec = {
          containers = [{
            name  = var.name
            image = var.image
            ports = [{ containerPort = var.container_port }]
            resources = {
              requests = {
                cpu    = var.cpu_request
                memory = var.memory_request
              }
              limits = {
                # No cpu limit on purpose: a CPU limit throttles rather than fails, and on a
                # demo whose point is how many pods fit, throttling only makes the result
                # harder to read. Memory is limited because exceeding it kills the container,
                # which is a failure worth having.
                memory = var.memory_limit
              }
            }
          }]
        }
      }
    }
  })
}
