# Every value here is a projection of local.outputs in main.tf. No output declares its
# own value expression: the same map is what the README on the VS Code instance is
# rendered from, so an output written directly here would be missing from that README and
# nothing would report it - the apply succeeds either way (rules.md H-2).
#
# description is the one exception. Terraform does not allow an expression there
# ("Variables not allowed"), so the wording exists as a literal in both places while the
# value still exists in only one.
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
  description = "API server endpoint. Public so the helm and kubectl providers could reach it during apply"
}
output "log_group" {
  value       = local.outputs.log_group.value
  description = "Where container logs land, with the retention period Terraform set. The _monolithic template let the collector create this group, leaving it with no expiry"
}
output "addon_configuration" {
  value       = local.outputs.addon_configuration.value
  description = "The JSON the adot add-on received, so a key in the wrong place is visible rather than silently ignored (rules.md E-5)"
}
output "collector_role" {
  value       = local.outputs.collector_role.value
  description = "IRSA role the container logs collector assumes. Its trust policy names a service account the add-on creates, not one this configuration chooses"
}
output "permission_check_command" {
  value       = local.outputs.permission_check_command.value
  description = "The RBAC that lets EKS install the add-on, which the _monolithic template applied from a URL on the bastion"
}
output "collector_status_command" {
  value       = local.outputs.collector_status_command.value
  description = "Whether the operator turned the collector object into a DaemonSet"
}
output "cert_manager_command" {
  value       = local.outputs.cert_manager_command.value
  description = "cert-manager's pods. The operator's webhook certificate comes from here, and this is the usual reason the add-on installs and collects nothing"
}
output "collector_log_command" {
  value       = local.outputs.collector_log_command.value
  description = "The collector's own log, where an AccessDenied from CloudWatch Logs is the only visible sign of a permissions problem"
}
output "log_stream_command" {
  value       = local.outputs.log_stream_command.value
  description = "Streams in the destination group with their last write time - the quickest check that events are arriving"
}
output "log_tail_command" {
  value       = local.outputs.log_tail_command.value
  description = "Follows the collected container logs"
}
output "workload_note" {
  value       = local.outputs.workload_note.value
  description = "Lists what is running, since the collected output is the cluster's own components until something else is deployed"
}
output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "Re-points kubectl on the instance at the cluster. User data already ran this"
}
