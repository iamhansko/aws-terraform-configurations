# Every value here is a projection of local.outputs in main.tf, which the README written
# onto the VS Code instance renders from the same map - so no value expression exists
# twice, and an output cannot be added without also appearing in that README
# (rules.md B-5/H-2).
#
# description is the one thing that cannot be projected: Terraform rejects an expression
# in an output's description ("Variables not allowed"), so the wording is a literal on
# both sides.
output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "Open the IDE here. Every kubectl command below is meant to be run from its terminal, and the update itself is watched from there"
}
output "cluster_name" {
  value       = local.outputs.cluster_name.value
  description = "Name of the EKS cluster"
}
output "cluster_endpoint" {
  value       = local.outputs.cluster_endpoint.value
  description = "API server endpoint. Public so the kubectl provider could reach it during apply - narrow public_access_cidrs to your own address"
}
output "node_group" {
  value       = local.outputs.node_group.value
  description = "The node group this project updates, and how many of its nodes EKS is allowed to take out of service at once"
}
output "launch_template" {
  value       = local.outputs.launch_template.value
  description = "The template, the version the node group is running, and the newest version that exists. The two differ while an update is pending"
}
output "disruption_budget" {
  value       = local.outputs.disruption_budget.value
  description = "What the update has to respect: the budget, the replica count and how long a replacement pod stays NotReady"
}
output "force_update_version" {
  value       = local.outputs.force_update_version.value
  description = "Whether the update drains through the eviction API and honours the budget, or deletes pods and ignores it"
}
output "rollout_status_command" {
  value       = local.outputs.rollout_status_command.value
  description = "1. Waits for the workload to settle. Run it before starting the update"
}
output "pod_placement_command" {
  value       = local.outputs.pod_placement_command.value
  description = "2. Which node each pod is on. Run it again during the update to see pods leave one at a time"
}
output "node_marker_command" {
  value       = local.outputs.node_marker_command.value
  description = "3. Every instance in the node group with its Name tag, which is how old and new nodes are told apart"
}
output "trigger_update_command" {
  value       = local.outputs.trigger_update_command.value
  description = "4. Starts the managed node group update by creating a new launch template version"
}
output "pdb_status_command" {
  value       = local.outputs.pdb_status_command.value
  description = "5. The budget's live accounting. ALLOWED DISRUPTIONS is the number the drain waits on"
}
output "eviction_events_command" {
  value       = local.outputs.eviction_events_command.value
  description = "6. The cordons and evictions in order, which is the record that EKS drained rather than terminated"
}
output "describe_update_command" {
  value       = local.outputs.describe_update_command.value
  description = "7. The update's own status and phase from the EKS side, and where a PodEvictionFailure appears"
}
output "block_update_command" {
  value       = local.outputs.block_update_command.value
  description = "8. Makes the update fail with PodEvictionFailure on purpose, by allowing no disruption at all"
}
output "force_update_command" {
  value       = local.outputs.force_update_command.value
  description = "9. Pushes the same blocked update through by forcing it, which deletes the pods the budget protects"
}
output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "Re-points kubectl at the cluster. User data already ran this"
}
