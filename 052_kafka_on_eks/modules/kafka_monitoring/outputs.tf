output "pod_monitor_names" {
  value       = keys(local.pod_monitors)
  description = "PodMonitors this module created, all in the Kafka namespace"
}
output "dashboard_names" {
  value       = keys(local.dashboards)
  description = "Dashboard ConfigMaps this module created, in Grafana's namespace"
}
output "targets_command" {
  value       = "kubectl -n ${var.kafka_namespace} get podmonitor"
  description = "Lists the PodMonitors. Whether Prometheus is actually scraping them shows on its Status > Targets page"
}
