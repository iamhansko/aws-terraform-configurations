# The Ingress that puts Grafana behind an ALB. Not part of the blueprint, which reached Grafana by
# port-forward; 052 added it on top, and used to apply it from an SSM association after installing the
# AWS Load Balancer Controller with eksctl and helm on the workbench. The controller is a module of its
# own now and this is a kubectl_manifest (rules.md E-1/E-2).
resource "kubectl_manifest" "ingress" {
  yaml_body = yamlencode({
    apiVersion = "networking.k8s.io/v1"
    kind       = "Ingress"
    metadata = {
      name        = var.name
      namespace   = var.namespace
      annotations = var.annotations
    }
    spec = {
      # Without ingressClassName nothing reconciles the Ingress: it is created and never gets an
      # address (rules.md G-1).
      ingressClassName = var.ingress_class_name
      rules = [{
        http = {
          paths = [{
            path     = "/"
            pathType = "Prefix"
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

  # The controller puts ingress.k8s.aws/resources on the Ingress (aws-load-balancer-controller v2.14.1,
  # pkg/shared_constants/finalizers.go) and removes it only after deleting the ALB, its listeners and its
  # target groups. Without wait the DELETE returns at once, the controller is uninstalled next, and the
  # ALB is left running with nothing that will ever delete it (rules.md D-7). The root orders this module
  # after the controller for the same reason (rules.md D-4).
  wait = true
}
