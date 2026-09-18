# Every value here is derived from the module's variables rather than from the
# resources, so the outputs still resolve when create_pods is false and the
# resources have a count of zero (rules.md B-5).
output "web_pod_name" {
  value       = var.web_pod_name
  description = "Name of the web pod, which is also its app label value and the name of the Service in front of it"
}
output "stress_pod_name" {
  value       = var.stress_pod_name
  description = "Name of the stress pod, which is also its app label value"
}
output "web_service_fqdn" {
  value       = local.web_service_fqdn
  description = "Cluster DNS name the stress pod requests. Replaces the _monolithic template's hand-pasted pod IP, and is knowable at plan time because a Service name comes from configuration rather than from the scheduler"
}
output "pods_check_command" {
  value       = "kubectl -n ${var.namespace} get pods -o wide"
  description = "Command listing the demo pods and the node each landed on. The fargate-ip- node names are the point: one Fargate node per pod"
}
output "stress_log_command" {
  value       = "kubectl -n ${var.namespace} logs ${var.stress_pod_name} --tail 10"
  description = "Command showing the status codes the stress pod is getting back. A column of 200s means it is reaching the web pod through the Service, which is also what confirms CoreDNS is resolving"
}
