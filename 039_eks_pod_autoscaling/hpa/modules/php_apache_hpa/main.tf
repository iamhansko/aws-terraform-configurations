locals {
  selector_labels = { run = var.name }
}
# The _monolithic template built these three objects with four imperative kubectl
# calls from an SSM Association - create deployment, set resources, expose, autoscale
# - so nothing recorded what was created and re-running the association would fail on
# the already-existing Deployment. They are resources here (rules.md E-1), declared as
# raw manifests through alekc/kubectl because this module is applied alongside the
# cluster whose outputs configure the provider (rules.md E-2). Field names stay
# camelCase, as the Kubernetes API spells them (rules.md E-3).
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
            name  = var.name
            image = var.image
            ports = [{ containerPort = var.container_port }]
            # The whole reason the HPA works. Utilisation is measured against the
            # request, so a container without one gives the HPA nothing to divide by
            # and its target shows as <unknown> forever.
            resources = {
              requests = { cpu = var.cpu_request }
              limits   = var.cpu_limit == null ? null : { cpu = var.cpu_limit }
            }
          }]
        }
      }
    }
  })
  # spec.replicas has two owners once the HPA exists: this manifest sets the starting
  # value, and the HPA moves it from then on. Only that path is excluded, so a changed
  # image or cpu_request still reaches the cluster (rules.md E-8).
  ignore_fields = ["spec.replicas"]
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
      # ClusterIP: the load generator runs inside the cluster and reaches this by
      # service name, so nothing needs to be exposed outside it. This variant creates
      # no load balancer at all - compare keda_cloudwatch, which scales on an ALB's
      # request count and therefore needs one.
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
# The variant. Scaling is driven by measured CPU, which means the metrics-server
# addon has to be running for this to do anything: without it the HPA reports
# <unknown> against its target and holds the replica count where it is.
resource "kubectl_manifest" "horizontal_pod_autoscaler" {
  yaml_body = yamlencode({
    # autoscaling/v2, not the v1 that "kubectl autoscale --cpu-percent" writes for
    # compatibility. v2 states the metric explicitly, so what the HPA is measuring is
    # visible in the manifest rather than implied by a single percentage field.
    apiVersion = "autoscaling/v2"
    kind       = "HorizontalPodAutoscaler"
    metadata = {
      name      = var.name
      namespace = var.namespace
    }
    spec = {
      scaleTargetRef = {
        apiVersion = "apps/v1"
        kind       = "Deployment"
        name       = var.name
      }
      minReplicas = var.min_replicas
      maxReplicas = var.max_replicas
      metrics = [{
        type = "Resource"
        resource = {
          name = "cpu"
          target = {
            type               = "Utilization"
            averageUtilization = var.target_cpu_utilization_percentage
          }
        }
      }]
    }
  })
  # scaleTargetRef names the Deployment as a string rather than referencing an
  # attribute of it, so nothing else tells Terraform the Deployment has to exist
  # first (rules.md D-1). An HPA pointing at a missing target is accepted and then
  # reports FailedGetScale.
  depends_on = [kubectl_manifest.deployment]
}
