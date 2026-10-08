# The demo workload: a Deployment, the Service in front of it, and the Ingress the AWS Load
# Balancer Controller turns into an ALB.
#
# Declared manifests rather than a YAML document echoed out of an SSM Association, which is what
# the _monolithic template did in both VPCs - the same 60 lines twice, with two security group IDs
# substituted into an annotation string (rules.md E-1/E-2/E-3).
#
# Two things that copy got wrong are fixed here: the image was "nginx:latest" from Docker Hub,
# which is unpinned and rate-limited from a shared NAT address, and the pods had no resource
# requests at all.
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

resource "kubectl_manifest" "service" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Service"
    metadata = {
      name      = var.name
      namespace = var.namespace
    }
    spec = {
      # ClusterIP: the ALB the Ingress produces is the public path, and with target-type ip it
      # sends traffic straight to pod addresses - so this Service is a name and a selector rather
      # than a data path.
      type     = "ClusterIP"
      selector = { app = var.name }
      ports = [{
        port       = var.container_port
        targetPort = var.container_port
        protocol   = "TCP"
      }]
    }
  })

  depends_on = [kubectl_manifest.deployment]
}

resource "kubectl_manifest" "ingress" {
  yaml_body = yamlencode({
    apiVersion = "networking.k8s.io/v1"
    kind       = "Ingress"
    metadata = {
      name        = var.name
      namespace   = var.namespace
      annotations = var.ingress_annotations
    }
    spec = {
      # Without this the Ingress is created and no controller ever looks at it (rules.md G-1).
      ingressClassName = var.ingress_class_name
      rules = [{
        http = {
          paths = [{
            path     = "/"
            pathType = "Prefix"
            backend = {
              service = {
                name = var.name
                port = { number = var.container_port }
              }
            }
          }]
        }
      }]
    }
  })

  depends_on = [kubectl_manifest.service]
}
