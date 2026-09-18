output "namespace" {
  value       = var.namespace
  description = "Namespace holding the logging ConfigMap, re-exposed so the caller's verification commands do not restate it (rules.md B-5)"
}
output "configmap_name" {
  value       = var.configmap_name
  description = "Name of the logging ConfigMap"
}
output "log_group_names" {
  value       = [for sink in values(var.log_sinks) : sink.log_group_name]
  description = "CloudWatch log group names the OUTPUT blocks write to. Not Terraform resources - Fluent Bit creates them on first record while auto_create_group is true, so they do not exist until a matching pod has logged something"
}
output "log_sink_labels" {
  value       = keys(var.log_sinks)
  description = "The caller-chosen labels behind each OUTPUT block. A pod must carry app=<label> to match one"
}
output "configmap_check_command" {
  value       = "kubectl -n ${var.namespace} get configmap ${var.configmap_name} -o yaml"
  description = "Command printing the rendered Fluent Bit configuration as the cluster actually has it. The first thing to read when logs do not arrive (rules.md H-2)"
}
output "namespace_label_check_command" {
  value       = "kubectl get namespace ${var.namespace} --show-labels"
  description = "Command confirming the aws-observability: enabled label is present. Without that label EKS ignores the ConfigMap entirely and no pod gets a log router"
}
