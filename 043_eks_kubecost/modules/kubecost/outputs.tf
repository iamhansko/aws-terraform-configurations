output "release_name" {
  value       = helm_release.kubecost.name
  description = "Name of the Helm release"
}
output "namespace" {
  value       = var.namespace
  description = "Namespace Kubecost runs in, re-exposed so callers do not restate it (rules.md B-5)"
}
output "service_name" {
  value       = local.service_name
  description = "Name of the cost-analyzer Service the Ingress routes to, derived from the release name"
}
output "basic_auth_user" {
  value       = var.basic_auth_user
  description = "Username for the dashboard's basic auth, re-exposed so the caller's instructions do not restate it (rules.md B-5)"
}
output "basic_auth_enabled" {
  value       = var.create_basic_auth
  description = "Whether basic auth is in front of the dashboard. False means the dashboard is open to anyone who can reach the load balancer, because Kubecost has no authentication of its own"
}
output "rollout_command" {
  value       = "kubectl -n ${var.namespace} rollout status deployment ${local.service_name}"
  description = "Command confirming the cost-analyzer finished rolling out. Kubecost needs several minutes of cluster data before its dashboard shows costs rather than zeroes"
}
output "ingress_check_command" {
  value       = "kubectl -n ${var.namespace} get ingress ${var.ingress_name}"
  description = "Command showing the Ingress and the address it got. An empty ADDRESS means the ingress controller is not reconciling it - usually a class name mismatch"
}
