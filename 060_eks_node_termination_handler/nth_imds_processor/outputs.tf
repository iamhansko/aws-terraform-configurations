# Values are all projections of local.outputs in main.tf, so no expression is written twice and
# the README the SSM association writes cannot fall behind this file (rules.md B-5/H-2).
#
# description is the one thing that cannot come from the map: Terraform rejects an expression in
# an output's description with "Variables not allowed", so the wording exists literally in both
# places. The values do not.
output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "Open the IDE here. Every command below is meant to be run from its terminal, where kubectl, helm, eksctl, eks-node-viewer and ec2-spot-interrupter are already installed"
}
output "cluster_name" {
  value       = local.outputs.cluster_name.value
  description = "Name of the EKS cluster"
}
output "cluster_endpoint" {
  value       = local.outputs.cluster_endpoint.value
  description = "API server endpoint. Public so the helm and kubectl providers could reach it during apply - narrow public_access_cidrs to your own address"
}
output "handler_mode" {
  value       = local.outputs.handler_mode.value
  description = "IMDS mode: a DaemonSet with one pod per node, each reading only its own instance metadata. It needs no queue, no IAM role and no credentials - and it cannot see an Auto Scaling scale-in, because no instance can learn that about itself. nth_queue_processor is the variant that can"
}
output "handler_status_command" {
  value       = local.outputs.handler_status_command.value
  description = "desired and ready should both equal the node count. A node without a handler pod is a node that will vanish without being drained, and nothing else reports that"
}
output "node_view_command" {
  value       = local.outputs.node_view_command.value
  description = "Leave this running in one terminal for the whole demo. A node going away and a replacement joining is the result, and neither is visible from the FIS console the CLI drives"
}
output "workload_placement_command" {
  value       = local.outputs.workload_placement_command.value
  description = "Run this before interrupting anything and keep the output. The replicas are spread across the nodes by a topologySpreadConstraint, which the _monolithic template had no equivalent of - without it the scheduler could stack most of them on one node and interrupting another would drain nothing"
}
output "spot_instance_list_command" {
  value       = local.outputs.spot_instance_list_command.value
  description = "The CLI takes instance IDs, so this is how to get one. Every node here is spot, which is why the node group's capacity type is not a free choice in this variant"
}
output "spot_interrupt_command" {
  value       = local.outputs.spot_interrupt_command.value
  description = "Substitute an instance ID from the list above. The CLI sends a rebalance recommendation immediately and the two-minute interruption notice after the delay, building a FIS experiment template, running it and deleting it again. Not something the apply does: it takes a node away"
}
output "handler_log_command" {
  value       = local.outputs.handler_log_command.value
  description = "The notice it read from instance metadata and the drain it performed. With rebalance draining on, the first entry is the rebalance recommendation rather than the interruption - the node is already empty by the time the notice arrives"
}
output "drain_events_command" {
  value       = local.outputs.drain_events_command.value
  description = "The record that the handler acted rather than the node simply vanishing. An instance reclaimed without a drain leaves no such events, which is exactly what this project is here to make visible"
}
output "workload_recovery_command" {
  value       = local.outputs.workload_recovery_command.value
  description = "Same command as the placement check. The pods that were on the interrupted node should be elsewhere and the total back at the replica count - with the disruption budget in place they moved in stages rather than all at once"
}
output "spot_interrupter_role_arn" {
  value       = local.outputs.spot_interrupter_role_arn.value
  description = "Named aws-fis-itn because the CLI looks for that exact name and would create its own if it were missing. The CLI prints this ARN in its experiment summary, which is the quickest confirmation it found this role rather than making one of its own"
}
output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "User data already ran this, so kubectl works out of the box. Re-run it if the kubeconfig is ever lost"
}
