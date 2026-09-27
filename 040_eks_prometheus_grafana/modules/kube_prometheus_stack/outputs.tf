output "release_name" {
  value       = helm_release.kube_prometheus_stack.name
  description = "Name of the Helm release"
}
output "namespace" {
  value       = var.namespace
  description = "Namespace the stack runs in, re-exposed so callers do not restate it (rules.md B-5)"
}
output "grafana_admin_user" {
  value       = var.grafana_admin_user
  description = "Grafana admin username, re-exposed so the caller's instructions do not restate it (rules.md B-5)"
}
output "grafana_password_command" {
  value       = "kubectl -n ${var.namespace} get secret ${var.release_name}-grafana -o jsonpath='{.data.admin-password}' | base64 -d"
  description = "Command reading the Grafana admin password back out of the cluster. Exposed as a command rather than the value itself so the password does not get written to the instance README, which is served by a code-server with no authentication (rules.md H-2)"
}
output "ingress_check_command" {
  value       = "kubectl -n ${var.namespace} get ingress"
  description = "Command listing the three Ingresses and the address each one got. An empty ADDRESS column means the ingress controller for that class is not reconciling it"
}
