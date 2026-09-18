# Every output is a projection of local.outputs in main.tf, which is also what the
# README written onto the bastion is rendered from (rules.md H-2). No value expression
# is written here: an output that built its own value would be missing from that README
# and the apply would succeed either way. The check is a count - the number of output
# blocks here must equal the number of entries in local.outputs.
output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "URL to access the code-server web UI on the bastion"
}
output "cluster_names" {
  value       = local.outputs.cluster_names.value
  description = "Names of the six EKS clusters, one per Node Monitoring Agent condition"
}
output "contexts_command" {
  value       = local.outputs.contexts_command.value
  description = "Command listing the kubeconfig contexts user data created, one per cluster"
}
output "node_conditions_command" {
  value       = local.outputs.node_conditions_command.value
  description = "Command reading a cluster's node conditions"
}
output "per_scenario_conditions" {
  value       = local.outputs.per_scenario_conditions.value
  description = "Per-scenario commands checking the specific condition each cluster demonstrates"
}
output "node_repair_command" {
  value       = local.outputs.node_repair_command.value
  description = "Command showing the managed node group's node repair configuration"
}
output "agent_log_command" {
  value       = local.outputs.agent_log_command.value
  description = "Command tailing a cluster's Node Monitoring Agent log from CloudWatch"
}
output "agent_pods_command" {
  value       = local.outputs.agent_pods_command.value
  description = "Command listing the agent's DaemonSet pods"
}
output "destroy_note" {
  value       = local.outputs.destroy_note.value
  description = "Reminder that six clusters and eighteen nodes bill continuously"
}
