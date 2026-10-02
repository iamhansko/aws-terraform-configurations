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
  description = "Two mechanisms, not one. The handler runs in IMDS mode as a DaemonSet and covers every node, including the managed node group Karpenter does not manage. Karpenter reads its own SQS queue and covers only the nodes it provisioned - but it also launches a replacement, which the handler never does"
}
output "handler_status_command" {
  value       = local.outputs.handler_status_command.value
  description = "desired and ready should both equal the node count, Karpenter's nodes included. A node without a handler pod is a node that will vanish without being drained, and nothing else reports that"
}
output "node_view_command" {
  value       = local.outputs.node_view_command.value
  description = "Leave this running in one terminal for the whole demo. A node going away and a replacement joining is the result, and neither is visible from the FIS console the CLI drives"
}
output "workload_placement_command" {
  value       = local.outputs.workload_placement_command.value
  description = "Run this before interrupting anything and keep the output. Every pod should be on a Karpenter node, not on the managed node group - a Pending pod means the nodeSelector matched no pool"
}
output "spot_instance_list_command" {
  value       = local.outputs.spot_instance_list_command.value
  description = "The CLI takes instance IDs, so this is how to get one. Only the Karpenter pool's nodes are spot - the managed node group is on-demand and cannot be interrupted"
}
output "spot_interrupt_command" {
  value       = local.outputs.spot_interrupt_command.value
  description = "Substitute an instance ID from the list above. The CLI sends a rebalance recommendation immediately and the two-minute interruption notice after the delay, building a FIS experiment template, running it and deleting it again. Not something the apply does: it takes a node away"
}
output "handler_log_command" {
  value       = local.outputs.handler_log_command.value
  description = "The notice the handler read from instance metadata and the drain it performed. On a Karpenter node this overlaps with Karpenter's own log, which is the duplicated draining the module comment describes"
}
output "drain_events_command" {
  value       = local.outputs.drain_events_command.value
  description = "The record that something acted rather than the node simply vanishing. An instance reclaimed without a drain leaves no such events, which is exactly what this project is here to make visible"
}
output "workload_recovery_command" {
  value       = local.outputs.workload_recovery_command.value
  description = "Same command as the placement check. The pods that were on the interrupted node should be elsewhere and the total back at the replica count - with the disruption budget in place they moved in stages rather than all at once"
}
output "spot_interrupter_role_arn" {
  value       = local.outputs.spot_interrupter_role_arn.value
  description = "Named aws-fis-itn because the CLI looks for that exact name and would create its own if it were missing. The CLI prints this ARN in its experiment summary, which is the quickest confirmation it found this role rather than making one of its own"
}
output "karpenter_node_list_command" {
  value       = local.outputs.karpenter_node_list_command.value
  description = "Karpenter's nodes carry a nodepool label and a capacity type of spot; the managed node group's are on-demand. After an interruption the spot node should have a different name and instance ID than before - that is Karpenter having launched a replacement, which the termination handler on its own would not do"
}
output "karpenter_log_command" {
  value       = local.outputs.karpenter_log_command.value
  description = "The controller logs the notice it read from its queue and the replacement it launched. This is the half the termination handler does not cover: if the node went away but nothing took its place, the queue name or the controller's SQS permissions are where to look"
}
output "karpenter_queue_depth_command" {
  value       = local.outputs.karpenter_queue_depth_command.value
  description = "Normally zero, because the controller deletes each message as it acts on it. A number that stays above zero means it is not polling - usually a wrong settings.interruptionQueue or an SQS permission missing from its policy, neither of which produces an error anywhere"
}
output "karpenter_controller_policy_arn" {
  value       = local.outputs.karpenter_controller_policy_arn.value
  description = "Karpenter's published least-privilege policy, created here rather than substituting AdministratorAccess. Almost every statement is scoped by a kubernetes.io/cluster tag condition, so the controller can only act on resources it created for this cluster"
}
output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "User data already ran this, so kubectl works out of the box. Re-run it if the kubeconfig is ever lost"
}
