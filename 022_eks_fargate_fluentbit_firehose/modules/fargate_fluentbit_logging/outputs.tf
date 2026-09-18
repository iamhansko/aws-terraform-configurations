output "namespace" {
  value       = var.namespace
  description = "Namespace holding the logging ConfigMap, re-exposed so the caller's verification commands do not restate it (rules.md B-5)"
}
output "configmap_name" {
  value       = var.configmap_name
  description = "Name of the logging ConfigMap"
}
output "delivery_stream_name" {
  value       = var.delivery_stream_name
  description = "Delivery stream the ConfigMap actually points at, re-exposed so a mismatch with the firehose module is visible in outputs (rules.md B-5)"
}
output "configmap_check_command" {
  value       = "kubectl -n ${var.namespace} get configmap ${var.configmap_name} -o yaml"
  description = "Command printing the rendered Fluent Bit configuration as the cluster actually has it. The first thing to read when objects do not appear in the bucket (rules.md H-2)"
}
output "namespace_label_check_command" {
  value       = "kubectl get namespace ${var.namespace} --show-labels"
  description = "Command confirming the aws-observability: enabled label is present. Without that label EKS ignores the ConfigMap entirely and no pod gets a log router"
}
