# Every value here is a projection of local.outputs in main.tf, which the README written onto the
# VS Code instance renders from the same map - so no value expression exists twice, and an output
# cannot be added without also appearing in that README (rules.md B-5/H-2).
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
output "multi_nic_configuration" {
  value       = local.outputs.multi_nic_configuration.value
  description = "The three things the feature needs and reports none of: the CNI switch, a multi-card instance type, and the pod annotation"
}
output "network_card_check_command" {
  value       = local.outputs.network_card_check_command.value
  description = "1. Confirms the node's instance type has more than one network card, which is not the same as more than one interface"
}
output "cni_env_check_command" {
  value       = local.outputs.cni_env_check_command.value
  description = "2. Reads ENABLE_MULTI_NIC off the aws-node DaemonSet in the cluster rather than from Terraform"
}
output "rollout_status_command" {
  value       = local.outputs.rollout_status_command.value
  description = "3. Waits for the demo pod, which starts more slowly with multi-NIC on"
}
output "interface_list_command" {
  value       = local.outputs.interface_list_command.value
  description = "4. The whole demo: how many addresses the pod actually has"
}
output "comparison_command" {
  value       = local.outputs.comparison_command.value
  description = "5. Re-applies the same Deployment without the annotation, which is how to confirm the annotation is what made the difference"
}
output "cni_log_command" {
  value       = local.outputs.cni_log_command.value
  description = "6. The CNI's log, the only place that distinguishes a too-old addon from an unseen annotation"
}
output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "Re-points kubectl at the cluster. User data already ran this"
}
