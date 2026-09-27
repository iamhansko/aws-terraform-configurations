locals {
  selector_labels = { "app.kubernetes.io/name" = var.name }
  # The <namespace>/<ingress name> value the AWS Load Balancer Controller writes into
  # its ingress.k8s.aws/stack tag. A pre-created load balancer has to carry exactly
  # this to be adopted rather than duplicated, so it is derived here from the names
  # this module owns instead of being restated by the caller (rules.md B-5/G-3).
  stack_tag = "${var.namespace}/${var.name}"
}
# The _monolithic template wrote these three objects into a heredoc on the bastion
# and applied them with "kubectl apply -f ... || true" from an SSM Association - so
# a failure was swallowed and nothing tracked what was applied. They are resources
# here (rules.md E-1), declared as raw manifests through alekc/kubectl because this
# module is applied alongside the cluster whose outputs configure the provider
# (rules.md E-2). Field names stay camelCase, as the Kubernetes API spells them
# (rules.md E-3).
resource "kubectl_manifest" "deployment" {
  yaml_body = yamlencode({
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = var.name
      namespace = var.namespace
    }
    spec = {
      replicas = var.replicas
      selector = { matchLabels = local.selector_labels }
      template = {
        metadata = { labels = local.selector_labels }
        spec = {
          containers = [{
            name            = var.name
            image           = var.image
            imagePullPolicy = "Always"
            ports           = [{ containerPort = var.container_port }]
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
      # ClusterIP is enough because the ALB registers pod addresses directly with
      # target-type ip; only target-type instance would need a NodePort
      # (rules.md G-1).
      type     = "ClusterIP"
      selector = local.selector_labels
      ports = [{
        port       = var.container_port
        targetPort = var.container_port
        protocol   = "TCP"
      }]
    }
  })
}
resource "kubectl_manifest" "ingress" {
  yaml_body = yamlencode({
    apiVersion = "networking.k8s.io/v1"
    kind       = "Ingress"
    metadata = {
      name      = var.name
      namespace = var.namespace
      annotations = merge(
        {
          "alb.ingress.kubernetes.io/scheme"          = var.scheme
          "alb.ingress.kubernetes.io/target-type"     = var.target_type
          "alb.ingress.kubernetes.io/security-groups" = var.frontend_security_group_id
        },
        # Hands the pod-side rules to the controller. Requires the controller's
        # backend security group feature to be on; it refuses the combination
        # otherwise and says so only in its own log (rules.md G-2).
        var.manage_backend_security_group_rules ? {
          "alb.ingress.kubernetes.io/manage-backend-security-group-rules" = "true"
        } : {},
      )
    }
    spec = {
      # Without this no controller looks at the Ingress at all (rules.md G-1).
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

  # The Service is named in a string here, not referenced as an attribute, so
  # nothing else tells Terraform it has to exist first (rules.md D-1). An Ingress
  # pointing at a missing Service is accepted and then reports no healthy targets.
  depends_on = [kubectl_manifest.service, kubectl_manifest.deployment]
}
