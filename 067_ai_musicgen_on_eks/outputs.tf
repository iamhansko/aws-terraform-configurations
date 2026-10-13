# Every value here is a projection of local.outputs in main.tf, which the README written onto the VS Code
# instance renders from the same map - so no value expression exists twice, and an output cannot be added
# without also appearing in that README (rules.md B-5/H-2).
#
# description is the one thing that cannot be projected: Terraform rejects an expression in an output's
# description ("Variables not allowed"), so the wording is a literal on both sides.
output "vscode_port_forward_command" {
  value       = local.outputs.vscode_port_forward_command.value
  description = "Optional SSM port-forward command. The public vscode_url is reachable from the detected My IP by default; this tunnel uses the SSM agent's outbound connection and needs no inbound rule"
}
output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "Public IDE URL, reachable from the detected My IP by default or every IPv4 source when allow_inbound_from_anywhere is true. Its kubeconfig has one context per cluster"
}
output "clusters" {
  value       = local.outputs.clusters.value
  description = "The two clusters, identical except for the device plugin's configuration"
}
output "gpu_capacity" {
  value       = local.outputs.gpu_capacity.value
  description = "How many GPUs each cluster's workload asks for, against how many the plugin advertises per card"
}
output "advertised_gpu_command" {
  value       = local.outputs.advertised_gpu_command.value
  description = "1. Reads the advertised GPU count on both clusters, which is where the difference shows"
}
output "smi_output_command" {
  value       = local.outputs.smi_output_command.value
  description = "2. nvidia-smi from inside a container, which proves the driver was injected"
}
output "pod_status_command" {
  value       = local.outputs.pod_status_command.value
  description = "3. Where the pods ended up on each cluster"
}
output "oversubscribe_command" {
  value       = local.outputs.oversubscribe_command.value
  description = "4. Asks the cluster without slicing for more GPUs than it has, which leaves pods Pending"
}
output "pending_reason_command" {
  value       = local.outputs.pending_reason_command.value
  description = "5. Reads why a pod is Pending, which distinguishes an exhausted count from a missing GPU"
}
output "time_slicing_config_command" {
  value       = local.outputs.time_slicing_config_command.value
  description = "6. The slicing configuration as the cluster holds it"
}
output "plugin_log_command" {
  value       = local.outputs.plugin_log_command.value
  description = "7. The plugin's log, the only place that says which configuration it loaded"
}
output "port_forward_command" {
  value       = local.outputs.port_forward_command.value
  description = "8. Opens the application's interface, which nothing publishes"
}
output "app_rollout_command" {
  value       = local.outputs.app_rollout_command.value
  description = "Waits for the application, whose image pull is the slowest part of the apply"
}
output "update_kubeconfig_commands" {
  value       = local.outputs.update_kubeconfig_commands.value
  description = "Re-points kubectl at both clusters, with one distinct context each"
}
