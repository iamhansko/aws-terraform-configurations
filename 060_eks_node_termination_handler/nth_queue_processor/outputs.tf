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
  description = "Queue mode: one Deployment for the whole cluster reading AWS events from SQS, with an IRSA role. IMDS mode is a DaemonSet whose pods read only their own instance and need no credentials at all - and cannot see an Auto Scaling scale-in, because no instance can learn that about itself. That event is what this variant's extra infrastructure buys"
}
output "handler_status_command" {
  value       = local.outputs.handler_status_command.value
  description = "A Deployment, not a DaemonSet - which is the visible difference from IMDS mode. Its replica count has nothing to do with the node count: one pod reading the queue covers the whole cluster"
}
output "managed_tag_check" {
  value       = local.outputs.managed_tag_check.value
  description = "With checkTagBeforeDraining on - the chart's default - the handler ignores any instance without this tag, and an untagged node group is silently never drained. Both node groups write it through their launch templates"
}
output "lifecycle_hooks_command" {
  value       = local.outputs.lifecycle_hooks_command.value
  description = "The terminating hook is what holds an instance in Terminating:Wait long enough for the handler to drain it, and what the handler then releases with CompleteLifecycleAction. Without it a scale-in terminates the node with no notice of any kind"
}
output "node_view_command" {
  value       = local.outputs.node_view_command.value
  description = "Leave this running in one terminal for the whole demo. A node going away and a replacement joining is the result, and neither is visible from the console"
}
output "workload_placement_command" {
  value       = local.outputs.workload_placement_command.value
  description = "Run this before touching anything and keep the output. The replicas are spread across the nodes by a topologySpreadConstraint, which the _monolithic template had no equivalent of - without it the scheduler could stack most of them on one node and removing another would drain nothing"
}
output "scale_in_command" {
  value       = local.outputs.scale_in_command.value
  description = "Removes a node by lowering the Auto Scaling group's desired capacity. Nothing is being reclaimed by EC2 here - the group itself is removing the instance, which produces no metadata notice at all, so in IMDS mode the node would simply vanish"
}
output "spot_instance_list_command" {
  value       = local.outputs.spot_instance_list_command.value
  description = "The other trigger, which both modes handle. Only the spot node group's instances can receive an interruption - the on-demand group's cannot, and the CLI refuses them"
}
output "spot_interrupt_command" {
  value       = local.outputs.spot_interrupt_command.value
  description = "Substitute an instance ID from the list above. The CLI sends a rebalance recommendation immediately and the two-minute interruption notice after the delay, building a FIS experiment template, running it and deleting it again. Not something the apply does: it takes a node away"
}
output "handler_log_command" {
  value       = local.outputs.handler_log_command.value
  description = "The message it read from the queue and the drain it performed. An AccessDenied on ReceiveMessage means the IRSA role is not being assumed; a message logged as skipped means the instance was missing the managed tag - and both look identical from outside, as a node that went away without a drain"
}
output "queue_depth_command" {
  value       = local.outputs.queue_depth_command.value
  description = "Normally zero, because the handler deletes each message as it acts on it. A number that stays above zero means it is not polling - usually a wrong queueURL or missing SQS permissions, neither of which produces an error anywhere visible"
}
output "failed_invocation_command" {
  value       = local.outputs.failed_invocation_command.value
  description = "The one failure with no other symptom: a rule that matches but cannot write to the queue counts a FailedInvocation and the notice is simply lost, so the node disappears without a drain and nothing in the cluster explains why"
}
output "drain_events_command" {
  value       = local.outputs.drain_events_command.value
  description = "The record that the handler acted rather than the node simply vanishing. Present because emit_kubernetes_events is on - with the chart's default it is off, and the only record of a drain is the handler's own log"
}
output "workload_recovery_command" {
  value       = local.outputs.workload_recovery_command.value
  description = "Same command as the placement check. The pods that were on the removed node should be elsewhere and the total back at the replica count - with the disruption budget in place they moved in stages, and the instance stayed in Terminating:Wait until that finished"
}
output "handler_role_arn" {
  value       = local.outputs.handler_role_arn.value
  description = "Queue mode needs AWS credentials where IMDS mode needs none, and this role is the whole of that difference on the IAM side. Its queue permissions are scoped to the one queue, where the _monolithic template granted them on every queue in the account"
}
output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "User data already ran this, so kubectl works out of the box. Re-run it if the kubeconfig is ever lost"
}
