locals {
  # Annotation keys have to be escaped for helm's --set, which treats an
  # unescaped dot as a path separator.
  annotation_prefix = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer"
}
resource "helm_release" "ingress_nginx" {
  name             = var.release_name
  repository       = var.chart_repository
  chart            = "ingress-nginx"
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = var.create_namespace
  # Holds the apply until the controller Deployment is Available, which is what
  # the _monolithic script's "helm ... --wait" did.
  wait    = true
  timeout = var.timeout_seconds

  set = concat([
    {
      name  = "controller.replicaCount"
      value = tostring(var.replica_count)
    },
    {
      name  = "controller.ingressClassResource.name"
      value = var.ingress_class_name
    },
    {
      name  = "controller.ingressClassResource.controllerValue"
      value = var.ingress_class_controller_value
    },
    {
      name  = "controller.ingressClassResource.default"
      value = tostring(var.set_as_default_ingress_class)
    },
    {
      name  = "controller.service.type"
      value = "LoadBalancer"
    },
    # The switch that decides which controller handles this Service, and the one
    # the _monolithic script omitted. Without it the in-tree AWS cloud provider
    # claims the Service and builds a Classic Load Balancer, silently ignoring
    # every annotation below - so the scheme, the target type and the security
    # groups all have no effect, and the pre-created NLB is never adopted because
    # the AWS Load Balancer Controller never looks at the Service at all
    # (rules.md G-1).
    {
      name  = "${local.annotation_prefix}-type"
      value = "external"
      # Annotation values must be strings; helm's --set would otherwise infer a
      # type and the API server rejects a non-string annotation (rules.md E-7).
      type = "string"
    },
    {
      name  = "${local.annotation_prefix}-scheme"
      value = var.scheme
      type  = "string"
    },
    # nlb-target-type, not target-type: the Service spelling carries the nlb-
    # prefix while the Ingress spelling does not, and the wrong one is ignored
    # rather than rejected (rules.md G-1).
    {
      name  = "${local.annotation_prefix}-nlb-target-type"
      value = var.nlb_target_type
      type  = "string"
    },
    # Naming the groups here is what makes the controller keep them on the load
    # balancer. An NLB can only be given security groups when it is created, so
    # the pre-created load balancer is built with this same list (rules.md G-3).
    {
      name  = "${local.annotation_prefix}-security-groups"
      value = join(",", var.frontend_security_group_ids)
      type  = "string"
    },
    {
      name  = "controller.service.port"
      value = tostring(var.service_port)
    },
    ],
    var.additional_set_values,
  )
}
