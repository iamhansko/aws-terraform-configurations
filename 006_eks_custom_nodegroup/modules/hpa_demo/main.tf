# Replaces the imperative sequence the _monolithic bastion ran:
#   kubectl create deployment php-apache --image=...
#   kubectl set resources deploy php-apache --requests=cpu=200m
#   kubectl expose deploy php-apache --port 80
#   kubectl autoscale deployment php-apache --cpu-percent=60 --min=1 --max=10
# Four imperative commands whose result existed only in the cluster; as
# resources, terraform plan shows drift and terraform destroy removes them
# (rules.md #18).
#
# Uses alekc/kubectl rather than hashicorp/kubernetes because this module is
# applied in the same terraform apply as the cluster whose outputs configure
# the provider (rules.md #26).
resource "kubectl_manifest" "hpa_demo_deployment" {
  yaml_body = yamlencode({
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = var.name
      namespace = var.namespace
      labels    = { app = var.name }
    }
    spec = {
      # Deliberately omits replicas: the HorizontalPodAutoscaler below owns
      # that field, and setting it here would make every apply fight the
      # autoscaler back down to the hardcoded value.
      selector = {
        matchLabels = { app = var.name }
      }
      template = {
        metadata = {
          labels = { app = var.name }
        }
        spec = {
          nodeSelector = var.node_selector
          containers = [{
            name  = var.name
            image = var.image
            ports = [{ containerPort = var.container_port }]
            resources = {
              # The CPU request is what the HPA measures utilization against,
              # so it is required rather than optional here.
              requests = { cpu = var.cpu_request }
              limits   = { cpu = var.cpu_limit }
            }
          }]
        }
      }
    }
  })
}
resource "kubectl_manifest" "hpa_demo_service" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Service"
    metadata = {
      name      = var.name
      namespace = var.namespace
      labels    = { app = var.name }
    }
    spec = {
      type     = "ClusterIP"
      selector = { app = var.name }
      ports = [{
        port       = var.service_port
        targetPort = var.container_port
        protocol   = "TCP"
      }]
    }
  })

  depends_on = [kubectl_manifest.hpa_demo_deployment]
}
resource "kubectl_manifest" "hpa_demo_autoscaler" {
  yaml_body = yamlencode({
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

  # scaleTargetRef.name is a literal string, so nothing else tells Terraform
  # the Deployment must exist first (rules.md #26).
  depends_on = [kubectl_manifest.hpa_demo_deployment]
}
