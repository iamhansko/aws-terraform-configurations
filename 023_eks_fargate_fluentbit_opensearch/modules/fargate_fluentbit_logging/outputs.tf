output "namespace" {
  value       = var.namespace
  description = "Namespace holding the logging ConfigMap, re-exposed so the caller's verification commands do not restate it (rules.md B-5)"
}
output "configmap_name" {
  value       = var.configmap_name
  description = "Name of the logging ConfigMap"
}
output "opensearch_endpoint" {
  value       = var.opensearch_endpoint
  description = "Domain endpoint the ConfigMap actually points at, re-exposed so a mismatch with the domain module is visible in outputs (rules.md B-5)"
}
output "index_name" {
  value       = var.index_name
  description = "Index Fluent Bit writes into, re-exposed so the caller's verification commands do not restate it (rules.md B-5)"
}
output "configmap_check_command" {
  value       = "kubectl -n ${var.namespace} get configmap ${var.configmap_name} -o yaml"
  description = "Command printing the rendered Fluent Bit configuration as the cluster actually has it. The first thing to read when nothing shows up in the index (rules.md H-2)"
}
output "namespace_label_check_command" {
  value       = "kubectl get namespace ${var.namespace} --show-labels"
  description = "Command confirming the aws-observability: enabled label is present. Without that label EKS ignores the ConfigMap entirely and no pod gets a log router"
}
