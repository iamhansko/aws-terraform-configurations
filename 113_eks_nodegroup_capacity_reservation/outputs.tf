# Every value here is a projection of local.outputs in main.tf, which the README written onto the workbench
# renders from the same map - so no value expression exists twice, and an output cannot be added without also
# appearing in that README (rules.md B-5/H-2).
#
# description is the one thing that cannot be projected: Terraform rejects an expression in an output's
# description ("Variables not allowed"), so the wording is a literal on both sides.
output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "Open the IDE here. kubectl is already pointed at the cluster"
}
output "cost_note" {
  value       = local.outputs.cost_note.value
  description = "Reserved capacity is billed whether or not an instance occupies it. Scaling the node group to zero does not stop it"
}
output "cluster_name" {
  value       = local.outputs.cluster_name.value
  description = "Name of the EKS cluster"
}
output "reservation" {
  value       = local.outputs.reservation.value
  description = "The capacity reservation: one type, one zone, and the cap on the node group's size"
}
output "reservation_usage_command" {
  value       = local.outputs.reservation_usage_command.value
  description = "1. Whether the node is actually occupying the reservation"
}
output "node_command" {
  value       = local.outputs.node_command.value
  description = "2. Whether the GPU node joined, and in which zone"
}
output "gpu_capacity_command" {
  value       = local.outputs.gpu_capacity_command.value
  description = "3. Whether the node advertises nvidia.com/gpu, which comes from the device plugin rather than the AMI"
}
output "device_plugin_daemon_set_command" {
  value       = local.outputs.device_plugin_daemon_set_command.value
  description = "4. Whether the device plugin's DaemonSet matched the GPU node. DESIRED 0 is a node labelling problem, and it reports as a successful install"
}
output "gpu_node_labels_note" {
  value       = local.outputs.gpu_node_labels_note.value
  description = "The labels on the GPU node. Delivered as kubelet flags in the NodeConfig, because EKS does not merge its own into the user data of a launch template that names an AMI"
}
output "gpu_workload_snippet" {
  value       = local.outputs.gpu_workload_snippet.value
  description = "5. A pod that requests a GPU and lands on the reserved node"
}
output "node_group_ami" {
  value       = local.outputs.node_group_ami.value
  description = "The EKS-optimized NVIDIA AMI, resolved from the cluster's own Kubernetes version rather than a hardcoded one"
}
output "node_group_update_strategy_note" {
  value       = local.outputs.node_group_update_strategy_note.value
  description = "Why a launch template change completes on a node group pinned to a full capacity reservation. MINIMAL drains before it launches; DEFAULT would wait on a reserved slot that cannot free up"
}
output "load_balancer_controller_command" {
  value       = local.outputs.load_balancer_controller_command.value
  description = "6. Whether the load balancer controller is running. It uses Pod Identity, not IRSA"
}
output "pod_identity_command" {
  value       = local.outputs.pod_identity_command.value
  description = "7. The Pod Identity association that replaces IRSA's service account annotation"
}
output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "Re-points kubectl at the cluster. User data already ran this"
}
output "private_key_command" {
  value       = local.outputs.private_key_command.value
  description = "Reads the workbench's SSH private key out of SSM Parameter Store"
}
