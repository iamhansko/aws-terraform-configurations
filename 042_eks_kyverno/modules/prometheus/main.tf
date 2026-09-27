locals {
  # The chart names its server Service <release>-server. The Grafana datasource has
  # to point at exactly this, so it is derived once here and re-exposed as an output
  # rather than spelled again by the caller (rules.md B-5).
  server_service_name = "${var.release_name}-server"
  server_url          = "http://${local.server_service_name}.${var.namespace}.svc.cluster.local:${var.server_port}"
}
# The _monolithic template installed Prometheus by cloning kyverno/grafana-dashboard
# and running "kubectl apply -k examples/prometheus" against a directory inside it -
# a git clone on the bastion, so nothing recorded what was installed and a repeat
# apply would pick up whatever upstream had changed. This is the same component as
# a pinned chart instead (rules.md E-1), which is also what makes the datasource
# address below knowable from configuration.
resource "helm_release" "prometheus" {
  name             = var.release_name
  repository       = var.chart_repository
  chart            = "prometheus"
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = var.create_namespace
  wait             = true
  timeout          = var.timeout_seconds

  set = concat([
    {
      name  = "server.service.servicePort"
      value = tostring(var.server_port)
    },
    {
      # Off deliberately: there is no EBS CSI driver and no default StorageClass on
      # this cluster, so an enabled claim stays Pending and takes the whole release
      # down with it on a timeout.
      name  = "server.persistentVolume.enabled"
      value = tostring(var.persistent_volume_enabled)
    },
    {
      name  = "server.global.scrape_interval"
      value = var.scrape_interval
    },
    # The dashboards read policy-report metrics from Kyverno's own exporter, not
    # from node or kubelet metrics, so the subcharts that collect those are off.
    # They are the bulk of what the chart would otherwise schedule.
    {
      name  = "alertmanager.enabled"
      value = "false"
    },
    {
      name  = "prometheus-pushgateway.enabled"
      value = "false"
    },
    ],
    var.additional_set_values,
  )
}
