locals {
  labels = { app = var.name }
  # Derived from the name rather than taken separately, so a response cannot claim to come from a
  # service other than the one that answered (rules.md B-1).
  pod_name_label = var.pod_name_label == null ? "${var.name} handler pod" : var.pod_name_label
}
# One backend behind the Gateway: a Deployment of AWS's sample HTTP server and the ClusterIP Service
# in front of it.
#
# Nothing about either object mentions VPC Lattice. The controller finds them through the HTTPRoute's
# backendRef, builds a Lattice target group from the Service, and registers the pods' addresses in it -
# so the Service is a normal ClusterIP and the traffic does not go through it at all.
#
# The _monolithic template echoed four of these into files on the bastion and applied them with
# kubectl, so none of it was in state (rules.md E-1/E-2).
resource "kubectl_manifest" "deployment" {
  yaml_body = yamlencode({
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = var.name
      namespace = var.namespace
      labels    = local.labels
    }
    spec = {
      replicas = var.replicas
      selector = { matchLabels = local.labels }
      template = {
        metadata = { labels = local.labels }
        spec = {
          containers = [{
            name  = var.name
            image = var.image
            ports = [{
              name          = "http"
              containerPort = var.container_port
            }]
            env = [{
              # What the server puts in its response body, which is how a request routed to one backend
              # is told from a request routed to another.
              name  = "PodName"
              value = local.pod_name_label
            }]
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
      # ClusterIP, left implicit by the _monolithic template and stated here. It matters that it is not
      # a LoadBalancer: VPC Lattice is what fronts these services, and a Service of type LoadBalancer
      # would quietly add a load balancer per backend to the account.
      type     = "ClusterIP"
      selector = local.labels
      ports = [{
        protocol   = "TCP"
        port       = var.service_port
        targetPort = var.container_port
      }]
    }
  })

  # Nothing on this Service mentions Lattice, but the controller still owns a piece of it: once an
  # HTTPRoute names this Service as a backendRef the controller builds a Lattice target group from it and
  # puts a finalizer on the object, so clearing that finalizer is what deregisters the targets and deletes
  # the target group. Without wait the DELETE returns while the object is still Terminating and the target
  # group outlives the destroy - which is exactly what happened here, leaving three k8s-default-* target
  # groups behind in the account (rules.md D-7).
  #
  # The finalizer is "service.ki8s.aws/resources", with the typo, as of controller v1.1.5. Grepping for
  # service.k8s.aws finds nothing.
  #
  # The Deployment above needs no such flag: the controller registers pod addresses as targets but puts no
  # finalizer on pods or Deployments, and the target group deletion is what deregisters them.
  wait = true

  depends_on = [kubectl_manifest.deployment]
}
