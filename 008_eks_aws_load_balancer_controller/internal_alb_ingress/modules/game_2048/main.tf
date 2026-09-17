# Replaces the _monolithic design, which wrote a 2048.yaml manifest into the
# bastion's home directory from user data and then ran "kubectl apply -f" over
# an SSM association (rules.md E-1). The manifest's embedded
# ${aws_security_group...id} interpolation became a plain string once written to
# disk, so nothing connected the two afterwards; here the security group ID
# arrives as an annotation value that Terraform tracks.
#
# Uses alekc/kubectl rather than hashicorp/kubernetes because this module is
# applied in the same terraform apply as the cluster whose outputs configure the
# provider (rules.md E-2).
locals {
  # The kubectl argument pair naming whichever object carries the load
  # balancer's address: the Ingress when one fronts the Service, otherwise the
  # Service itself. Defined once so the commands this module exposes cannot
  # disagree about which object to read (rules.md B-5).
  load_balancer_object = var.create_ingress ? "ingress ${var.ingress_name}" : "service ${var.service_name}"
  # The controller writes the load balancer's DNS name into the same
  # status.loadBalancer field on both kinds, so one expression covers both
  # shapes.
  load_balancer_hostname_command = "kubectl -n ${var.namespace} get ${local.load_balancer_object} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
}
resource "kubectl_manifest" "namespace" {
  count = var.create_namespace ? 1 : 0
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Namespace"
    metadata = {
      name = var.namespace
    }
  })
}
resource "kubectl_manifest" "deployment" {
  yaml_body = yamlencode({
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = var.deployment_name
      namespace = var.namespace
    }
    spec = {
      replicas = var.replica_count
      selector = {
        matchLabels = { "app.kubernetes.io/name" = var.app_label }
      }
      template = {
        metadata = {
          labels = { "app.kubernetes.io/name" = var.app_label }
        }
        spec = {
          containers = [{
            name            = var.app_label
            image           = var.image
            imagePullPolicy = "Always"
            ports           = [{ containerPort = var.container_port }]
          }]
        }
      }
    }
  })

  # metadata.namespace is a literal string, so nothing else tells Terraform the
  # Namespace must exist first (rules.md E-2).
  depends_on = [kubectl_manifest.namespace]
}
resource "kubectl_manifest" "service" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Service"
    metadata = {
      name        = var.service_name
      namespace   = var.namespace
      annotations = var.service_annotations
    }
    spec = {
      # NodePort/ClusterIP when an Ingress fronts this Service (the ALB shape),
      # LoadBalancer when the Service itself is the load balancer (the NLB
      # shape).
      type     = var.service_type
      selector = { "app.kubernetes.io/name" = var.app_label }
      ports = [{
        port       = var.service_port
        targetPort = var.container_port
        protocol   = "TCP"
      }]
    }
  })

  depends_on = [kubectl_manifest.deployment]
}
resource "kubectl_manifest" "ingress" {
  count = var.create_ingress ? 1 : 0
  yaml_body = yamlencode({
    apiVersion = "networking.k8s.io/v1"
    kind       = "Ingress"
    metadata = {
      name      = var.ingress_name
      namespace = var.namespace
      # Annotations are what actually shape the ALB: scheme, target type, and
      # which security group the controller attaches.
      annotations = var.ingress_annotations
    }
    spec = {
      ingressClassName = var.ingress_class_name
      rules = [{
        http = {
          paths = [{
            path     = var.ingress_path
            pathType = var.ingress_path_type
            backend = {
              service = {
                name = var.service_name
                port = { number = var.service_port }
              }
            }
          }]
        }
      }]
    }
  })

  # backend.service.name is a literal string, so nothing else orders this after
  # the Service (rules.md E-2).
  depends_on = [kubectl_manifest.service]
}
