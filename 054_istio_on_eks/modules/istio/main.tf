# Istio, as three charts installed in a fixed order.
#
# The _monolithic template did this from an SSM Association that wrote a shell script
# onto the bastion and ran it: helm repo add, then three helm upgrade --install calls
# with unpinned versions, then a sleep 60. Nothing about the mesh was in Terraform
# state, so plan showed no diff, destroy removed none of it, and the chart versions
# were whatever the repository served that day (rules.md E-1).
#
# Kept as one module rather than three, because the three charts are one component:
# istiod reads CRDs that base installs, and the gateway's proxy is configured by
# istiod and built from the same release. Splitting them would only move the ordering
# below into the root (rules.md C-2).
locals {
  # Values are given as YAML rather than through set entries. set runs each value
  # through helm's type inference, which is exactly wrong for annotations: Kubernetes
  # requires annotation values to be strings, and an inferred bool or number is
  # rejected by the API server when the object is decoded (rules.md E-7). The security
  # group annotation makes it worse - its value is a comma-separated list, and set
  # treats an unescaped comma as a separator between values. yamlencode sidesteps both:
  # a Terraform string becomes a quoted YAML string, commas and all.
  gateway_values = {
    service = {
      type = "LoadBalancer"
      # Replaces the chart's default port list. See var.service_ports for why the
      # chart's 15021 and 443 entries are deliberately not carried over.
      ports = [
        for name, port in var.service_ports : {
          name = name
          port = port
          # The gateway proxy binds the service port directly rather than an internal
          # one - the chart grants it the capability to bind below 1024 for exactly
          # this - so targetPort and port are the same number. That is also the port
          # the pod-side security group rule in the root has to open, since
          # target-type is ip and the load balancer talks to the pod, not the Service.
          targetPort = port
          protocol   = "TCP"
        }
      ]
      annotations = merge(
        {
          # Without this the Service is claimed by the in-tree AWS cloud provider,
          # which builds a Classic Load Balancer and ignores every other annotation
          # here - scheme, target type, security groups, health check, all of it. The
          # Service still gets an EXTERNAL-IP, so it reads as success; the
          # pre-created network load balancer is simply never adopted and sits with
          # no listeners (rules.md G-1).
          #
          # The controller's service mutator webhook would also claim the Service by
          # injecting spec.loadBalancerClass, which is how the _monolithic template
          # got away with omitting this. That webhook is off in this project because
          # its failurePolicy: Fail gates every Service creation in the cluster on a
          # Ready controller pod, and this project creates Services from four charts
          # right after installing it (rules.md G-4). Naming the controller here is
          # the explicit alternative.
          "service.beta.kubernetes.io/aws-load-balancer-type"                 = "external"
          "service.beta.kubernetes.io/aws-load-balancer-scheme"               = var.scheme
          "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type"      = var.nlb_target_type
          "service.beta.kubernetes.io/aws-load-balancer-healthcheck-protocol" = "HTTP"
          "service.beta.kubernetes.io/aws-load-balancer-healthcheck-port"     = tostring(var.health_check_port)
          "service.beta.kubernetes.io/aws-load-balancer-healthcheck-path"     = var.health_check_path
          "service.beta.kubernetes.io/aws-load-balancer-attributes"           = "load_balancing.cross_zone.enabled=${var.cross_zone_enabled}"
        },
        length(var.frontend_security_group_ids) > 0 ? {
          "service.beta.kubernetes.io/aws-load-balancer-security-groups" = join(",", var.frontend_security_group_ids)
        } : {},
      )
    }
  }
}
# CRDs and the cluster-scoped pieces istiod needs before it starts.
resource "helm_release" "base" {
  name             = "istio-base"
  repository       = var.chart_repository
  chart            = "base"
  version          = var.chart_version
  namespace        = var.control_plane_namespace
  create_namespace = true
  wait             = true
  timeout          = var.timeout_seconds

  set = [
    {
      # Marks this install as the "default" revision, which is what makes the
      # revisionless istio-injection=enabled label work. Without it the injection
      # webhook matches only namespaces naming a specific revision, so a labelled
      # namespace gets no sidecars - and a pod with no sidecar is simply not in the
      # mesh, with nothing reporting that it was meant to be.
      name  = "defaultRevision"
      value = "default"
    },
  ]
}
# The control plane: configuration distribution, certificate issuance, and the
# sidecar injection webhook.
resource "helm_release" "istiod" {
  name             = "istiod"
  repository       = var.chart_repository
  chart            = "istiod"
  version          = var.chart_version
  namespace        = var.control_plane_namespace
  create_namespace = true
  wait             = true
  timeout          = var.timeout_seconds

  # The chart references CRDs base installs, and helm does not infer that from the
  # namespace they share (rules.md D-1).
  depends_on = [helm_release.base]
}
# The data plane edge. This chart's Service is what the AWS Load Balancer Controller
# turns into - or in this project, adopts as - a network load balancer.
resource "helm_release" "gateway" {
  name             = var.gateway_release_name
  repository       = var.chart_repository
  chart            = "gateway"
  version          = var.chart_version
  namespace        = var.gateway_namespace
  create_namespace = true
  # wait = true is what the _monolithic template's "sleep 60" was reaching for. It
  # holds the apply until the gateway Deployment is Available, which is the point
  # after which a load balancer exists for the controller to reconcile.
  wait    = true
  timeout = var.timeout_seconds

  values = [yamlencode(local.gateway_values)]

  # The gateway pod is an injected proxy: it gets its listeners from istiod and stays
  # unready until it can reach it. Waiting here turns a slow failure into a clear one.
  depends_on = [helm_release.istiod]
}
