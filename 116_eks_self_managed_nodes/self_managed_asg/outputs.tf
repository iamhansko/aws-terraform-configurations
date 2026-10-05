# Every value here is a projection of local.outputs in main.tf. No output in this file builds
# its own expression: the same map feeds the README written onto the workbench, and an output
# declared outside it would be missing from that README with nothing to signal the gap
# (rules.md H-2).
#
# description is the one thing that cannot come from the map. Terraform rejects an expression in
# an output's description ("Variables not allowed"), so the wording is literal in both places
# while the value stays in one.

output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "Open the IDE here and run every command below from its terminal"
}

output "cluster_name" {
  value       = local.outputs.cluster_name.value
  description = "Name of the EKS cluster"
}

output "node_group_name" {
  value       = local.outputs.node_group_name.value
  description = "The group holding the cluster's nodes"
}

output "service_cidr" {
  value       = local.outputs.service_cidr.value
  description = "Both are written into every node's NodeConfig, because a self-managed node has no way to discover them"
}

output "node_status_command" {
  value       = local.outputs.node_status_command.value
  description = "One entry per InService instance, all Ready"
}

output "instances_command" {
  value       = local.outputs.instances_command.value
  description = "The group's own view"
}

output "deployment_status_command" {
  value       = local.outputs.deployment_status_command.value
  description = "Ten are requested"
}

output "pending_pods_command" {
  value       = local.outputs.pending_pods_command.value
  description = "Run kubectl describe on one of these"
}

output "scale_command" {
  value       = local.outputs.scale_command.value
  description = "Adds the second instance"
}

output "pod_distribution_command" {
  value       = local.outputs.pod_distribution_command.value
  description = "Run it before and after scaling"
}

output "bootstrap_log_command" {
  value       = local.outputs.bootstrap_log_command.value
  description = "The only place a rejected NodeConfig is explained"
}

output "api_server_probe_command" {
  value       = local.outputs.api_server_probe_command.value
  description = "Useful when kubectl behaves oddly and the question is whether the endpoint or the client is at fault - this bypasses the kubeconfig entirely"
}

output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "User data already ran this, so kubectl works out of the box"
}
