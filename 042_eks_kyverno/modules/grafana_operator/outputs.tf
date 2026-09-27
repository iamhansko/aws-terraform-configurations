output "release_name" {
  value       = helm_release.grafana_operator.name
  description = "Name of the operator's Helm release"
}
output "namespace" {
  value       = var.namespace
  description = "Namespace the operator and Grafana run in, re-exposed so callers do not restate it (rules.md B-5)"
}
output "grafana_instance_name" {
  value       = var.grafana_instance_name
  description = "Name of the Grafana custom resource"
}
output "admin_user" {
  value       = var.admin_user
  description = "Grafana admin username, re-exposed so the caller's instructions do not restate it (rules.md B-5)"
}
output "dashboard_label_value" {
  value       = var.dashboard_label_value
  description = "Value of the 'dashboards' label tying dashboards and datasources to this instance. Re-exposed because a mismatch here is the usual reason Grafana comes up with no data and no error (rules.md B-5)"
}
output "ingress_check_command" {
  value       = "kubectl -n ${var.namespace} get ingress"
  description = "Command showing the Ingress the operator created for Grafana and the address it got. An empty ADDRESS means the ingress controller is not reconciling it, usually a class name mismatch"
}
output "datasource_check_command" {
  value       = "kubectl -n ${var.namespace} get grafanadatasource ${var.datasource_name} -o jsonpath='{.status}'"
  description = "Command showing whether the operator applied the datasource to the Grafana instance. This is where an instanceSelector that matches nothing shows up"
}
