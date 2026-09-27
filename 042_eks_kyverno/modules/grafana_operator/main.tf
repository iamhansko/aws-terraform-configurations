resource "helm_release" "grafana_operator" {
  name = var.release_name
  # No repository argument: an oci:// reference carries the registry itself.
  chart            = var.chart
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = var.create_namespace
  # Holds the apply until the operator is serving. The custom resources below are
  # rejected outright if the CRDs the operator installs are not registered yet,
  # which is what "--wait" was doing in the _monolithic script.
  wait    = true
  timeout = var.timeout_seconds
}
# Grafana itself, declared as the custom resource the operator watches rather than
# as a chart. The manifest keeps the API's own camelCase field names instead of
# being rewritten into HCL conventions (rules.md E-3).
resource "kubectl_manifest" "grafana" {
  yaml_body = yamlencode({
    apiVersion = "grafana.integreatly.org/v1beta1"
    kind       = "Grafana"
    metadata = {
      name      = var.grafana_instance_name
      namespace = var.namespace
      # The operator matches dashboards and datasources to an instance by this
      # label. A datasource whose instanceSelector does not match it is created
      # without error and then belongs to no Grafana.
      labels = { dashboards = var.dashboard_label_value }
    }
    spec = {
      config = {
        log = { mode = "console" }
        auth = {
          # Quoted: Grafana's config is an ini file, so every value has to reach it
          # as a string. yamlencode of a bool would render disable_login_form: false
          # and the operator rejects the non-string value.
          disable_login_form = "false"
        }
        security = {
          admin_user     = var.admin_user
          admin_password = var.admin_password
        }
      }
      ingress = {
        spec = {
          ingressClassName = var.ingress_class_name
          rules = [{
            http = {
              paths = [{
                path     = "/"
                pathType = "Prefix"
                backend = {
                  service = {
                    name = var.service_name
                    port = { number = var.service_port }
                  }
                }
              }]
            }
          }]
        }
      }
    }
  })

  # The CRD this resource uses is installed by the release above, and a manifest for
  # an unregistered kind fails rather than waiting. Nothing in the values expresses
  # that, so it is stated (rules.md D-1/E-3).
  depends_on = [helm_release.grafana_operator]
}
resource "kubectl_manifest" "grafana_datasource" {
  yaml_body = yamlencode({
    apiVersion = "grafana.integreatly.org/v1beta1"
    kind       = "GrafanaDatasource"
    metadata = {
      name      = var.datasource_name
      namespace = var.namespace
    }
    spec = {
      # Has to match the Grafana instance's labels above, or this datasource is
      # attached to no instance and Grafana shows dashboards with no data.
      instanceSelector = {
        matchLabels = { dashboards = var.dashboard_label_value }
      }
      datasource = {
        name      = var.datasource_name
        type      = "prometheus"
        access    = "proxy"
        url       = var.prometheus_url
        isDefault = true
      }
    }
  })

  depends_on = [helm_release.grafana_operator, kubectl_manifest.grafana]
}
