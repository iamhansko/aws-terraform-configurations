# Kiali, installed the way the project intends it: an operator, a Kiali CR for the
# operator to act on, and an Ingress the AWS Load Balancer Controller turns into - or
# here, matches against a pre-created - ALB.
#
# The _monolithic template ran the same two steps from a shell script on the bastion,
# with the Ingress written as a heredoc inside an SSM Association parameter. Declared
# as resources they are in state, the annotations are reviewable in plan, and destroy
# removes the Ingress while the controller is still alive to clean up the load
# balancer (rules.md E-1/E-2/D-4).
locals {
  # YAML rather than set entries. cr.spec is a free-form object the chart copies
  # straight into the custom resource, and its keys are snake_case with underscores -
  # expressing that through set means escaping nothing but reading much worse, and any
  # value helm infers as a bool or number lands in the CR as that type. yamlencode
  # keeps the structure visible and the types intact (rules.md E-7).
  operator_values = {
    cr = {
      create    = true
      name      = var.name
      namespace = var.namespace
      spec = {
        # anonymous means no login screen. See var.auth_strategy.
        auth = {
          strategy = var.auth_strategy
        }
        deployment = {
          cluster_wide_access = var.cluster_wide_access
        }
        istio_namespace = var.istio_namespace
        server = {
          port = var.server_port
          # Without this Kiali serves from / and answers 404 to everything the
          # Ingress forwards. See var.web_root.
          web_root = var.web_root
        }
      }
    }
  }
}
resource "helm_release" "kiali_operator" {
  name       = "kiali-operator"
  repository = var.chart_repository
  chart      = "kiali-operator"
  version    = var.chart_version
  namespace  = var.namespace
  # The namespace already exists - the istio base chart created it - but this stays
  # true so the module does not depend on that being the case.
  create_namespace = true
  wait             = true
  timeout          = var.timeout_seconds

  values = [yamlencode(local.operator_values)]
}
resource "kubectl_manifest" "kiali_ingress" {
  yaml_body = yamlencode({
    apiVersion = "networking.k8s.io/v1"
    kind       = "Ingress"
    metadata = {
      name      = var.name
      namespace = var.namespace
      annotations = merge(
        {
          "alb.ingress.kubernetes.io/scheme"      = var.scheme
          "alb.ingress.kubernetes.io/target-type" = var.target_type
          # The ALB's own health check. It has to be a path Kiali answers, which is
          # why it is web_root rather than /: with the server serving under /kiali, a
          # check against / returns 404 and every target is marked unhealthy while
          # the pod is perfectly fine.
          "alb.ingress.kubernetes.io/healthcheck-path" = var.web_root
        },
        length(var.frontend_security_group_ids) > 0 ? {
          # Note the alb. prefix here against the service.beta.kubernetes.io. prefix
          # the gateway Service uses for the same concept. Using one form where the
          # other belongs is not rejected - the annotation is simply ignored, and the
          # controller attaches a security group of its own making instead
          # (rules.md G-1).
          "alb.ingress.kubernetes.io/security-groups" = join(",", var.frontend_security_group_ids)
        } : {},
      )
    }
    spec = {
      # Omitting this leaves the Ingress unclaimed by any controller, which produces
      # no error and no load balancer (rules.md G-1).
      ingressClassName = var.ingress_class_name
      rules = [{
        http = {
          paths = [{
            path     = var.web_root
            pathType = "Prefix"
            backend = {
              service = {
                name = var.name
                port = {
                  number = var.server_port
                }
              }
            }
          }]
        }
      }]
    }
  })

  # The backend Service is created by the operator in response to the CR, so it does
  # not exist when this release finishes - wait = true above covers the operator pod,
  # not the server it goes on to build. The controller retries on the Service's
  # creation event, so the Ingress resolves a minute or two later; this ordering is
  # here because the namespace and the CR both have to exist first, and neither is
  # referenced as an attribute (rules.md D-1).
  depends_on = [helm_release.kiali_operator]
}
