output "name" {
  value       = var.name
  description = "Name shared by the demo Deployment, Service and HorizontalPodAutoscaler (rules.md B-5)"
}
output "namespace" {
  value       = var.namespace
  description = "Namespace the demo workload runs in"
}
output "load_generator_command" {
  value       = "kubectl run load-generator --image=busybox --restart=Never -n ${var.namespace} -- /bin/sh -c \"while true; do wget -q -O - http://${var.name}:${var.service_port}; done\""
  description = "Ready-to-run command that drives CPU load into the demo Service so the HorizontalPodAutoscaler scales up"
}
