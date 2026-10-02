# Datadog on EKS: the operator's chart, the Secret holding the API key, and the
# DatadogAgent custom resource the operator turns into the agent DaemonSet.
#
# All three in one module because they are one component - the DatadogAgent references the
# Secret by name and cannot be reconciled until the operator's CRDs exist, so splitting
# them would only move the coupling into the root (rules.md C-2).
#
# The _monolithic template did all of it from an SSM Association on the bastion:
#   helm install datadog-operator ... --wait
#   kubectl -n monitoring create secret generic datadog-secret --from-literal api-key=...
#   echo '<DatadogAgent yaml>' > manifests/datadog_agent.yaml && kubectl apply -f ...
# which put the API key into the association's parameters, where it is readable with
# "aws ssm describe-association" by anyone with that permission, and left none of the three
# in Terraform state (rules.md E-1).
resource "helm_release" "datadog_operator" {
  name             = var.release_name
  repository       = var.chart_repository
  chart            = "datadog-operator"
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = true
  # Holds the apply until the operator Deployment is Available, which is what the
  # _monolithic script's "--wait" did. It matters more than usual here: the DatadogAgent
  # CRD arrives with this release, and the custom resource below cannot be applied until
  # that CRD is registered.
  wait    = true
  timeout = var.timeout_seconds

  set = var.additional_set_values
}
# The API key, as a Secret rather than a "kubectl create secret" in a shell.
#
# kubectl_manifest's yaml_body is marked sensitive by the provider, so the key is not
# printed by plan or apply. It is still stored in Terraform state in the clear, as every
# Terraform-managed secret is - the gain over the shell version is that it is no longer
# also sitting in an SSM association parameter.
resource "kubectl_manifest" "api_key_secret" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Secret"
    type       = "Opaque"
    metadata = {
      name      = var.secret_name
      namespace = var.namespace
    }
    # stringData, not data: it takes the raw value, so the key is not base64-encoded here.
    # Encoding it by hand is the common mistake - base64 of the key is accepted as a valid
    # Secret and then decoded into nonsense, which the agent reports as an invalid key.
    stringData = {
      "api-key" = var.api_key
    }
  })

  # The namespace is created by the Helm release above, and metadata.namespace is a literal
  # string rather than an attribute reference, so nothing else orders this after it
  # (rules.md D-1).
  depends_on = [helm_release.datadog_operator]
}
# What the operator actually reconciles. Declared as a manifest because the provider has no
# typed resource for a third-party CRD, keeping the original camelCase field names rather
# than rewritten YAML (rules.md E-3).
resource "kubectl_manifest" "datadog_agent" {
  yaml_body = yamlencode({
    apiVersion = "datadoghq.com/v2alpha1"
    kind       = "DatadogAgent"
    metadata = {
      name      = var.agent_name
      namespace = var.namespace
    }
    spec = {
      global = {
        site = var.site
        credentials = {
          apiSecret = {
            secretName = var.secret_name
            keyName    = "api-key"
          }
        }
      }
      features = {
        logCollection = {
          enabled             = var.enable_log_collection
          containerCollectAll = var.collect_all_containers
        }
      }
    }
  })

  # Two separate reasons, both invisible to Terraform's graph: the CRD this object's kind
  # refers to arrives with the operator's chart, and secretName is a literal string rather
  # than a reference to the Secret resource (rules.md D-1/E-2).
  depends_on = [
    helm_release.datadog_operator,
    kubectl_manifest.api_key_secret,
  ]
}
