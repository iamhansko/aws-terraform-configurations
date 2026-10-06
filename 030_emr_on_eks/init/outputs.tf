# Every value here is a projection of local.outputs in main.tf. No output in this file builds its
# own expression: the same map feeds the README written onto the bastion, and an output declared
# outside it would be missing from that README with nothing to signal the gap (rules.md H-2).
#
# description is the one thing that cannot come from the map. Terraform rejects an expression in an
# output's description ("Variables not allowed"), so the wording is literal in both places while the
# value stays in one.

output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "Open the IDE here"
}

output "cluster_name" {
  value       = local.outputs.cluster_name.value
  description = "Name of the EKS cluster"
}

output "variant_note" {
  value       = local.outputs.variant_note.value
  description = "The base layer: a cluster with Karpenter, three node pools and the GPU device plugin, and nothing on top of it"
}

output "node_pools_command" {
  value       = local.outputs.node_pools_command.value
  description = "Three pools: one CPU pool and two GPU pools"
}

output "nodes_command" {
  value       = local.outputs.nodes_command.value
  description = "Starts with the core node group's nodes only"
}

output "gpu_capacity_command" {
  value       = local.outputs.gpu_capacity_command.value
  description = "Zero until a GPU node exists, which Karpenter provisions only when something asks for one"
}

output "demo_pod_command" {
  value       = local.outputs.demo_pod_command.value
  description = "Selects the x86-cpu pool's labels, so Karpenter has to provision an m5 instance for it"
}

output "demo_pod_cleanup_command" {
  value       = local.outputs.demo_pod_cleanup_command.value
  description = "Karpenter consolidates the node away once it is empty, after the pool's consolidateAfter window"
}

output "karpenter_log_command" {
  value       = local.outputs.karpenter_log_command.value
  description = "Where an unschedulable pod is explained"
}

output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "User data already ran this, so kubectl works out of the box"
}
