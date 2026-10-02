# The load that makes the demo visible. Enhanced subnet discovery does nothing until a
# node's own subnet runs out of addresses, so something has to run the /28s dry - and a
# pod whose only job is to hold one VPC address is the cheapest way to do that.
#
# The _monolithic template wrote this manifest with a heredoc inside an SSM Association
# and ran kubectl apply on the bastion. That leaves the Deployment outside Terraform
# entirely: no diff in plan, nothing to destroy, and the replica count reachable only by
# editing a shell script inside a string. Declared as resources it is in state, the
# replica count is a variable, and terraform destroy removes it while the cluster is
# still there to remove it from (rules.md E-1/E-2/D-4).
resource "kubectl_manifest" "namespace" {
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
      name      = var.name
      namespace = var.namespace
    }
    spec = {
      replicas = var.replicas
      selector = {
        matchLabels = { app = var.name }
      }
      template = {
        metadata = {
          labels = { app = var.name }
        }
        spec = {
          # Nothing is being drained gracefully here; zero keeps the pods from lingering
          # for 30 seconds - and holding their addresses - every time the count drops.
          terminationGracePeriodSeconds = 0
          containers = [{
            name  = var.name
            image = var.image
            resources = {
              requests = {
                cpu = var.cpu_request
              }
            }
          }]
        }
      }
    }
  })

  # metadata.namespace is a literal string, so nothing in Terraform's graph knows the
  # namespace has to exist first (rules.md D-1/E-2). Without this the Deployment can be
  # applied into a namespace that is not there yet.
  depends_on = [kubectl_manifest.namespace]
}
