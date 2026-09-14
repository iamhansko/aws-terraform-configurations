output "namespace" {
  value       = var.namespace
  description = "Namespace kube-ops-view runs in, re-exposed so callers reference one source of truth (rules.md #5)"
}
output "service_name" {
  value       = var.name
  description = "Name of the Service. Declared directly rather than derived from a Helm fullname template, so it is exactly this value - the chart-based version produced <release>-kube-ops-view, which made port-forward commands built from the release name wrong"
}
output "service_type" {
  value       = var.service_type
  description = "Service type actually applied"
}
output "port_forward_command" {
  value       = "kubectl -n ${var.namespace} port-forward svc/${var.name} 8080:${var.service_port}"
  description = "Reaches the dashboard on http://localhost:8080 without publishing it, which is how to use this module with service_type = ClusterIP"
}
output "describe_command" {
  value       = "kubectl -n ${var.namespace} get service ${var.name}"
  description = "Shows the Service, including the load balancer address once the controller has reconciled it when service_type is LoadBalancer"
}
