output "release_name" {
  value       = helm_release.prometheus.name
  description = "Name of the Helm release"
}
output "namespace" {
  value       = var.namespace
  description = "Namespace Prometheus runs in, re-exposed so callers do not restate it (rules.md B-5)"
}
output "server_service_name" {
  value       = local.server_service_name
  description = "Name of the Prometheus server Service, derived from the release name"
}
output "server_url" {
  value       = local.server_url
  description = "In-cluster URL of the Prometheus server. The Grafana datasource takes this rather than rebuilding the address, so the datasource cannot point at a service name the chart did not create (rules.md B-5)"
}
output "check_command" {
  value       = "kubectl -n ${var.namespace} get pods -l app.kubernetes.io/name=prometheus"
  description = "Command listing the Prometheus pods. If Grafana shows no data, this is the first thing to check - a Pending pod here usually means persistent_volume_enabled was turned on without a default StorageClass"
}
