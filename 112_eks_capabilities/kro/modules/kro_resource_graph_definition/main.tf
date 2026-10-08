# A kro ResourceGraphDefinition: a new Kubernetes API, defined as a graph of other objects.
#
# This is the whole point of kro and the thing the _monolithic template never created. Its variant
# installed a capability - and even that one asked for type = "ACK" while naming itself kro, so the
# cluster came up with the ACK controllers installed and nothing kro-related anywhere.
#
# Declared as a kubectl_manifest rather than applied from the workbench so it is in Terraform state
# and `terraform destroy` removes it. That matters here: deleting an RGD deletes the CRD it
# generated, and deleting the CRD deletes every instance of it (rules.md E-1/E-3).
resource "kubectl_manifest" "resource_graph_definition" {
  yaml_body = yamlencode({
    apiVersion = "kro.run/v1alpha1"
    kind       = "ResourceGraphDefinition"
    metadata = {
      name = var.name
    }
    spec = {
      # The API this definition creates. kro turns this into a CRD, so after it goes Active the
      # cluster serves a kind that did not exist before - which is why the instance cannot be
      # applied in the same step.
      schema = {
        apiVersion = var.api_version
        kind       = var.kind
        # kro's Simple Schema rather than OpenAPI: a type name per field, with an optional default
        # after a pipe. What the caller of the new API is allowed to set.
        spec = {
          name     = "string"
          image    = "string | default=\"${var.default_image}\""
          replicas = "integer | default=${var.default_replicas}"
        }
        # Fields read back out of the objects the graph created. Every $${...} here is a kro
        # expression, escaped so Terraform leaves it alone rather than trying to interpolate it.
        status = {
          availableReplicas = "$${deployment.status.availableReplicas}"
          serviceName       = "$${service.metadata.name}"
        }
      }
      # The graph. kro reads the references between templates to work out the order itself, so
      # nothing here states that the Service comes after the Deployment - the reference to
      # deployment.spec.selector is what establishes it.
      resources = [
        {
          id = "deployment"
          template = {
            apiVersion = "apps/v1"
            kind       = "Deployment"
            metadata = {
              name = "$${schema.spec.name}"
            }
            spec = {
              replicas = "$${schema.spec.replicas}"
              selector = {
                matchLabels = {
                  app = "$${schema.spec.name}"
                }
              }
              template = {
                metadata = {
                  labels = {
                    app = "$${schema.spec.name}"
                  }
                }
                spec = {
                  containers = [{
                    name  = "nginx"
                    image = "$${schema.spec.image}"
                    ports = [{ containerPort = var.container_port }]
                  }]
                }
              }
            }
          }
        },
        {
          id = "service"
          template = {
            apiVersion = "v1"
            kind       = "Service"
            metadata = {
              name = "$${schema.spec.name}"
            }
            spec = {
              # Read from the Deployment rather than restated, which is also what tells kro the
              # Service depends on it.
              selector = "$${deployment.spec.selector.matchLabels}"
              ports = [{
                port       = var.service_port
                targetPort = var.container_port
              }]
            }
          }
        },
      ]
    }
  })

  # The ResourceGraphDefinition CRD does not exist until the capability has installed kro, and a
  # manifest whose kind is unregistered fails with "no matches for kind" rather than waiting for it.
  #
  # This also makes `terraform destroy` delete the RGD while kro is still running, so the CRD and
  # its instances are cleaned up rather than left with finalizers and no controller (rules.md D-4).
  depends_on = [var.capability_dependency]
}
