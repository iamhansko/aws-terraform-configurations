locals {
  selector_labels = { app = var.name }
  vpa_name        = "${var.name}-vpa"
}
# The upstream hamster example, which the _monolithic template applied by cloning
# kubernetes/autoscaler onto the bastion and running "kubectl apply -f
# ./autoscaler/vertical-pod-autoscaler/examples/hamster.yaml" from an SSM Association.
# The manifests are resources here (rules.md E-1), declared as raw manifests through
# alekc/kubectl because this module is applied alongside the cluster whose outputs
# configure the provider (rules.md E-2). Field names stay camelCase, as the Kubernetes
# API spells them (rules.md E-3).
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
          securityContext = {
            runAsNonRoot = true
            runAsUser    = var.run_as_user
          }
          containers = [{
            name    = var.name
            image   = var.image
            command = ["/bin/sh"]
            # Burns CPU for half a second, sleeps for half a second, forever. A
            # steady partial load, which is what gives the recommender a stable
            # number to converge on rather than a spike to overreact to.
            args = ["-c", "while true; do timeout 0.5s yes >/dev/null; sleep 0.5s; done"]
            # Deliberately below what the loop above actually consumes. The whole
            # demo is the distance between this and the recommendation.
            resources = {
              requests = {
                cpu    = var.cpu_request
                memory = var.memory_request
              }
            }
          }]
        }
      }
    }
  })
  # In Initial, Recreate or Auto mode the admission controller rewrites these requests
  # as replacement pods are admitted, so this one path has two owners: the manifest
  # sets the starting point and the VPA moves it from there (rules.md E-8).
  #
  # Indexed at 0 rather than excluding the whole containers list. There is no wildcard
  # in these paths, and a list prefix would take the image and args with it - so a
  # changed image would stop reaching the cluster with plan reporting no changes. This
  # Deployment has exactly one container, so the index is safe to pin; a variable
  # number of containers would have no way to express this narrowly.
  ignore_fields = ["spec.template.spec.containers.0.resources"]
}
# The variant. A VerticalPodAutoscaler is a custom resource, so its CRD has to exist
# before this is accepted - the chart in modules/vertical_pod_autoscaler installs it
# from the chart's crds/ directory, and the root orders this module after that release.
resource "kubectl_manifest" "vertical_pod_autoscaler" {
  yaml_body = yamlencode({
    apiVersion = "autoscaling.k8s.io/v1"
    kind       = "VerticalPodAutoscaler"
    metadata = {
      name      = local.vpa_name
      namespace = var.namespace
    }
    spec = {
      targetRef = {
        apiVersion = "apps/v1"
        kind       = "Deployment"
        name       = var.name
      }
      updatePolicy = {
        updateMode = var.update_mode
      }
      resourcePolicy = {
        containerPolicies = [{
          # '*' rather than the container name, as upstream has it: the policy then
          # keeps applying if a sidecar is added.
          containerName = "*"
          minAllowed = {
            cpu    = var.min_allowed_cpu
            memory = var.min_allowed_memory
          }
          maxAllowed = {
            cpu    = var.max_allowed_cpu
            memory = var.max_allowed_memory
          }
          controlledResources = var.controlled_resources
        }]
      }
    }
  })
  # targetRef names the Deployment as a string rather than referencing an attribute of
  # it, so nothing else tells Terraform the Deployment has to exist first
  # (rules.md D-1). A VPA pointing at a missing target is accepted and simply never
  # produces a recommendation.
  depends_on = [kubectl_manifest.deployment]
}
