# Every value here is a projection of local.outputs in main.tf, which the README written onto the VS
# Code instance renders from the same map - so no value expression exists twice, and an output cannot
# be added without also appearing in that README (rules.md B-5/H-2).
#
# description is the one thing that cannot be projected: Terraform rejects an expression in an
# output's description ("Variables not allowed"), so the wording is a literal on both sides.
output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "Open the IDE here. The kubectl commands below are meant to be run from its terminal"
}
output "cluster_name" {
  value       = local.outputs.cluster_name.value
  description = "Name of the EKS cluster"
}
output "cluster_endpoint" {
  value       = local.outputs.cluster_endpoint.value
  description = "API server endpoint. Public so the kubectl provider could reach it during apply"
}
output "multus_install" {
  value       = local.outputs.multus_install.value
  description = "The pinned Multus image and the CNI configuration it delegates the primary interface to"
}
output "interface_plan" {
  value       = local.outputs.interface_plan.value
  description = "What the nodes create, what the attachment names and what the VPC was told to keep clear - all derived from the same variables"
}
output "node_interface_check_command" {
  value       = local.outputs.node_interface_check_command.value
  description = "1. The extra ENIs the nodes created for themselves, found by their no_manage tag"
}
output "multus_daemon_check_command" {
  value       = local.outputs.multus_daemon_check_command.value
  description = "2. Whether the Multus DaemonSet is ready on every node"
}
output "cni_config_check_command" {
  value       = local.outputs.cni_config_check_command.value
  description = "3. Whether Multus generated its delegating CNI configuration on the node"
}
output "rollout_status_command" {
  value       = local.outputs.rollout_status_command.value
  description = "4. Waits for the demo pods. A timeout means the attachment could not be satisfied"
}
output "interface_list_command" {
  value       = local.outputs.interface_list_command.value
  description = "5. The interfaces a demo pod actually has"
}
output "network_status_command" {
  value       = local.outputs.network_status_command.value
  description = "6. The annotation Multus writes back onto each pod listing what it attached"
}
output "dedicated_eni_check_command" {
  value       = local.outputs.dedicated_eni_check_command.value
  description = "Whether each pod got a secondary ENI of its own, which is the point of this arrangement: one line per MAC with a count of 1"
}
output "pod_events_command" {
  value       = local.outputs.pod_events_command.value
  description = "8. Where a failed attachment is reported, when a pod will not start"
}
output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "Re-points kubectl at the cluster. User data already ran this"
}
output "multus_security_group_eni_check_command" {
  value       = local.outputs.multus_security_group_eni_check_command.value
  description = "Lists every interface attached with the Multus security group, which should be exactly the secondary ones"
}
output "whereabouts_allocations_command" {
  value       = local.outputs.whereabouts_allocations_command.value
  description = "The cluster-wide address allocations, as IPPool objects - one per range"
}
output "secondary_address_check_command" {
  value       = local.outputs.secondary_address_check_command.value
  description = "Whether each pod's Multus address is registered on its ENI, which is what lets the VPC route to it"
}
output "connectivity_check_command" {
  value       = local.outputs.connectivity_check_command.value
  description = "Sends traffic over the secondary network, between two pods of one attachment - the only check here that puts a packet on it rather than reading state"
}
