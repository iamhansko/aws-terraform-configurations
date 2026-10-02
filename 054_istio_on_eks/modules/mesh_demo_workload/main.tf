# Something for the mesh to carry.
#
# The _monolithic template installed Istio and Kiali and stopped there, which leaves a
# demo that cannot be checked: the load balancer URL refuses connections, because
# Envoy only binds a traffic port once a Gateway resource declares a server on it, and
# Kiali's graph is empty, because no workload is in the mesh. These five objects are
# the smallest thing that makes both observable - and being Terraform resources they
# are in state, appear in plan, and are removed in order on destroy rather than left
# for someone to kubectl apply (rules.md E-1/E-2).
resource "kubectl_manifest" "namespace" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Namespace"
    metadata = {
      name = var.namespace
      # The label is what puts this namespace in the mesh. See var.injection_label.
      labels = var.injection_label
    }
  })
}
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
          labels = {
            app = var.name
            # Istio's convention for distinguishing versions of the same service.
            # Kiali reads it to label the nodes in its graph; without it the graph
            # shows the workload as "latest" with no version breakdown.
            version = "v1"
          }
        }
        spec = {
          containers = [{
            name  = var.name
            image = var.image
            ports = [{
              name          = var.service_port_name
              containerPort = var.container_port
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

  # metadata.namespace is a literal string, so nothing in Terraform's graph knows the
  # namespace has to exist first - and here the ordering matters twice over, because
  # the injection label has to be on the namespace before these pods are created. A
  # pod created first gets no sidecar and stays that way until it is restarted
  # (rules.md D-1).
  depends_on = [kubectl_manifest.namespace]
}
resource "kubectl_manifest" "service" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Service"
    metadata = {
      name      = var.name
      namespace = var.namespace
      labels    = { app = var.name }
    }
    spec = {
      # ClusterIP, not LoadBalancer. Inbound traffic arrives at the ingress gateway
      # and is routed to this Service from inside the mesh, so it needs no address of
      # its own - and a second Service of type LoadBalancer here would mean a second
      # load balancer.
      type     = "ClusterIP"
      selector = { app = var.name }
      ports = [{
        # The name carries the protocol Istio applies to this port. See
        # var.service_port_name.
        name       = var.service_port_name
        port       = var.service_port
        targetPort = var.container_port
        protocol   = "TCP"
      }]
    }
  })

  depends_on = [kubectl_manifest.namespace]
}
# Istio's own Gateway and VirtualService, declared as manifests because neither has a
# typed resource in any provider (rules.md E-3). The field names are the upstream
# camelCase ones, copied as they appear in Istio's documentation rather than
# translated to HCL block syntax.
#
# Gateway binds a port on the shared ingress proxy; VirtualService says what to do
# with what arrives there. Both are needed: a Gateway with no VirtualService binds the
# port and then has no route, answering 404.
resource "kubectl_manifest" "gateway" {
  count = var.route_traffic ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "networking.istio.io/v1"
    kind       = "Gateway"
    metadata = {
      name      = var.name
      namespace = var.namespace
    }
    spec = {
      # Selects the gateway Deployment's pods, in another namespace. This is the one
      # field that fails silently: no controller validates that it matches anything.
      selector = var.gateway_selector
      servers = [{
        port = {
          number   = var.gateway_port
          name     = "http"
          protocol = "HTTP"
        }
        hosts = var.hosts
      }]
    }
  })

  depends_on = [kubectl_manifest.namespace]
}
resource "kubectl_manifest" "virtual_service" {
  count = var.route_traffic ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "networking.istio.io/v1"
    kind       = "VirtualService"
    metadata = {
      name      = var.name
      namespace = var.namespace
    }
    spec = {
      hosts = var.hosts
      # A bare name, which Istio resolves in this VirtualService's own namespace. A
      # Gateway in a different namespace would have to be written as
      # "<namespace>/<name>" here, and a name that resolves to no Gateway attaches
      # the routes to nothing.
      gateways = [var.name]
      http = [{
        route = [{
          destination = {
            # The fully qualified Service name. A short name would resolve against
            # the namespace the request came from rather than this one, which for
            # traffic entering through the gateway is the gateway's namespace.
            host = "${var.name}.${var.namespace}.svc.cluster.local"
            port = {
              number = var.service_port
            }
          }
        }]
      }]
    }
  })

  # The Gateway this attaches to must exist first; spec.gateways is a string, so
  # Terraform cannot see that (rules.md D-1).
  depends_on = [kubectl_manifest.namespace, kubectl_manifest.gateway]
}
