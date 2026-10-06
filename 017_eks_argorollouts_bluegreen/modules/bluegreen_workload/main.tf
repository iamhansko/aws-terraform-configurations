locals {
  # The two Services a blue/green Rollout needs. activeService keeps serving the old
  # version while previewService points at the new one, and promotion swaps the
  # selectors - Argo Rollouts writes the pod-template-hash selector into both, which
  # is why neither Service declares one here beyond the app label.
  common_selector = { app = var.app_label }
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
resource "kubectl_manifest" "active_service" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Service"
    metadata = {
      name      = var.active_service_name
      namespace = var.namespace
    }
    spec = {
      type     = "ClusterIP"
      selector = local.common_selector
      ports = [{
        port       = var.service_port
        targetPort = var.container_port
        protocol   = "TCP"
      }]
    }
  })

  # metadata.namespace is a literal string, so nothing else tells Terraform the
  # Namespace must exist first (rules.md E-2).
  depends_on = [kubectl_manifest.namespace]
}
resource "kubectl_manifest" "preview_service" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Service"
    metadata = {
      name      = var.preview_service_name
      namespace = var.namespace
    }
    spec = {
      type     = "ClusterIP"
      selector = local.common_selector
      ports = [{
        port       = var.service_port
        targetPort = var.container_port
        protocol   = "TCP"
      }]
    }
  })

  depends_on = [kubectl_manifest.namespace]
}
# The Rollout replaces the Deployment a normal workload would have. Its
# blue/green strategy names the target group ARN Terraform created, which is the
# substitution the _monolithic template did with sed against a YAML file on the
# bastion's disk - so nothing tied the manifest to the load balancer afterwards.
# Interpolating the module output means the ARN exists in one place (rules.md B-5).
resource "kubectl_manifest" "rollout" {
  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Rollout"
    metadata = {
      name      = var.rollout_name
      namespace = var.namespace
    }
    spec = {
      replicas = var.replica_count
      selector = {
        matchLabels = local.common_selector
      }
      template = {
        metadata = {
          labels = local.common_selector
        }
        spec = {
          containers = [{
            name  = var.app_label
            image = var.image
            ports = [{ containerPort = var.container_port }]
          }]
        }
      }
      strategy = {
        blueGreen = {
          activeService  = var.active_service_name
          previewService = var.preview_service_name
          # False so the demo pauses after the preview version is healthy and waits
          # for "kubectl argo rollouts promote". With it true the promotion happens
          # before anyone can watch it.
          autoPromotionEnabled = var.auto_promotion_enabled
          # The ARN Terraform created. Argo Rollouts registers and deregisters pod
          # IPs in this group as it promotes, which is why the target group's
          # membership is left out of Terraform's control (see the module that
          # creates it).
          activeMetadata = {
            labels = { role = "active" }
          }
          previewMetadata = {
            labels = { role = "preview" }
          }
        }
      }
    }
  })

  # The Rollout is only reconciled once the Argo Rollouts controller exists, and the
  # CRD it validates against is installed by that controller's chart. Ordering this
  # after the controller also makes terraform destroy remove the Rollout while the
  # controller is still running to clean up its ReplicaSets (rules.md D-4).
  depends_on = [kubectl_manifest.active_service, kubectl_manifest.preview_service]
}
# Binds the active Service to the target group Terraform created, which is what
# actually puts pod IPs behind the load balancer. The AWS Load Balancer Controller
# reconciles this custom resource; without it the target group stays empty and the
# load balancer answers 503 no matter how healthy the pods are.
resource "kubectl_manifest" "active_target_group_binding" {
  yaml_body = yamlencode({
    apiVersion = "elbv2.k8s.aws/v1beta1"
    kind       = "TargetGroupBinding"
    metadata = {
      name      = "${var.active_service_name}-tgb"
      namespace = var.namespace
    }
    spec = {
      serviceRef = {
        name = var.active_service_name
        port = var.service_port
      }
      targetGroupARN = var.active_target_group_arn
      targetType     = "ip"
    }
  })

  depends_on = [kubectl_manifest.active_service]
}
