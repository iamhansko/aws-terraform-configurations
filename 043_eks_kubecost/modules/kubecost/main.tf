locals {
  service_name = "${var.release_name}-cost-analyzer"
  # The upstream preset the _monolithic template passed with "helm -f <url>". Built
  # from chart_version so the values file and the chart can never be different
  # versions (rules.md B-5).
  eks_values_url = "https://raw.githubusercontent.com/kubecost/cost-analyzer-helm-chart/v${var.chart_version}/cost-analyzer/values-eks-cost-monitoring.yaml"
}
# Fetched rather than vendored so it stays the upstream file for this chart version.
# The cost is a plan-time network call: with no route to
# raw.githubusercontent.com the plan fails here rather than at apply.
data "http" "eks_cost_monitoring_values" {
  count = var.use_eks_cost_monitoring_values ? 1 : 0

  url = local.eks_values_url

  lifecycle {
    postcondition {
      condition     = self.status_code == 200
      error_message = "Could not fetch ${local.eks_values_url} (HTTP ${self.status_code}). The chart version may not exist upstream, or this machine has no route to raw.githubusercontent.com."
    }
  }
}
resource "helm_release" "kubecost" {
  name = var.release_name
  # No repository argument: an oci:// reference carries the registry itself.
  chart            = var.chart
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = var.create_namespace
  wait             = true
  timeout          = var.timeout_seconds

  # values is layered under set, so the explicit set entries below still win.
  values = var.use_eks_cost_monitoring_values ? [data.http.eks_cost_monitoring_values[0].response_body] : []

  set = concat(
    var.storage_class_name == null ? [] : [
      {
        name  = "prometheus.server.persistentVolume.storageClass"
        value = var.storage_class_name
      },
    ],
    var.additional_set_values,
  )
}
# Kubecost has no authentication of its own, so the only thing between the
# dashboard and the internet is this. The htpasswd file the _monolithic template
# built by shelling out to the httpd-tools binary is produced with Terraform's
# bcrypt() instead, which is the same format ingress-nginx validates.
resource "kubectl_manifest" "basic_auth" {
  count = var.create_basic_auth ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Secret"
    metadata = {
      name      = var.basic_auth_secret_name
      namespace = var.namespace
    }
    type = "Opaque"
    data = {
      # The key has to be "auth" - that is the filename ingress-nginx looks for
      # inside the Secret, and the reason the original used "htpasswd -c auth".
      auth = base64encode("${var.basic_auth_user}:${bcrypt(var.basic_auth_password)}")
    }
  })

  lifecycle {
    # bcrypt() salts randomly, so it returns a different hash on every plan and
    # this Secret would otherwise show a diff forever - and every apply would
    # invalidate the credential people are using. Same reasoning as the
    # timestamp() rollout trigger (rules.md E-4). Change the password by tainting
    # or replacing this resource deliberately.
    ignore_changes = [yaml_body]
  }

  depends_on = [helm_release.kubecost]
}
resource "kubectl_manifest" "ingress" {
  yaml_body = yamlencode({
    apiVersion = "networking.k8s.io/v1"
    kind       = "Ingress"
    metadata = {
      name      = var.ingress_name
      namespace = var.namespace
      # Field names stay camelCase, exactly as the Kubernetes API spells them
      # (rules.md E-3).
      annotations = var.create_basic_auth ? {
        "nginx.ingress.kubernetes.io/auth-type"   = "basic"
        "nginx.ingress.kubernetes.io/auth-secret" = var.basic_auth_secret_name
        "nginx.ingress.kubernetes.io/auth-realm"  = var.basic_auth_realm
      } : {}
    }
    spec = {
      ingressClassName = var.ingress_class_name
      rules = [{
        http = {
          paths = [{
            path     = "/"
            pathType = "Prefix"
            backend = {
              service = {
                name = local.service_name
                port = { number = var.service_port }
              }
            }
          }]
        }
      }]
    }
  })

  # The Service this routes to is named in a string, not referenced as an
  # attribute, so nothing else tells Terraform the release has to exist first
  # (rules.md D-1). The Secret likewise: ingress-nginx returns 503 for an Ingress
  # whose auth Secret is missing rather than serving it unauthenticated.
  depends_on = [helm_release.kubecost, kubectl_manifest.basic_auth]
}
