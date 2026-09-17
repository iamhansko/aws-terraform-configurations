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
output "load_balancer_hostname_command" {
  value       = var.service_type == "LoadBalancer" ? local.load_balancer_hostname_command : null
  description = "Command that prints just the load balancer's DNS name, or null when service_type is not LoadBalancer and there is none. The load balancer is created by the AWS Load Balancer Controller rather than by Terraform, so its address cannot be a Terraform output and has to be read from the cluster instead (rules.md #35/#38)"
}
output "load_balancer_fetch_command" {
  value       = var.service_type == "LoadBalancer" ? "curl -s http://$(${local.load_balancer_hostname_command})" : null
  description = "Command that fetches the dashboard through the load balancer, or null when service_type is not LoadBalancer. Built from load_balancer_hostname_command so both reference one source of truth (rules.md #5)"
}
output "container_port" {
  value       = var.container_port
  description = "Port the dashboard listens on inside the pod, and the Service's targetPort. Re-exposed because with an ip target type the load balancer registers pod IPs on this port, so a caller opening the node-side path has to allow exactly it rather than the Service port (rules.md #5/#38)"
}
