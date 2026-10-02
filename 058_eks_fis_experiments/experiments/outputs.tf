# Values are all projections of local.outputs in main.tf, so no expression is written
# twice and the README the SSM association writes cannot fall behind this file
# (rules.md B-5/H-2).
#
# description is the one thing that cannot come from the map: Terraform rejects an
# expression in an output's description with "Variables not allowed", so the wording
# exists literally in both places. The values do not.
output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "Open the IDE here. Every command below is meant to be run from its terminal, where kubectl, helm, eksctl and eks-node-viewer are already installed"
}
output "cluster_name" {
  value       = local.outputs.cluster_name.value
  description = "Name of the EKS cluster. Also the value of the karpenter.sh/discovery subnet tag and the aws:eks:cluster-name security group tag both EC2NodeClasses select on"
}
output "cluster_endpoint" {
  value       = local.outputs.cluster_endpoint.value
  description = "API server endpoint. Public so the helm and kubectl providers could reach it during apply - narrow public_access_cidrs to your own address"
}
output "node_view_command" {
  value       = local.outputs.node_view_command.value
  description = "Leave this running in one terminal for the whole demo. It is the view an experiment is judged by: a node disappearing and a replacement appearing is the result, and neither is visible in the FIS console"
}
output "node_list_command" {
  value       = local.outputs.node_list_command.value
  description = "One spot node and one on-demand node, each with the pool that made it. Both experiments target instances by the Name tag Karpenter wrote onto these, so if a pool provisioned nothing its experiment will fail on empty target resolution rather than do nothing"
}
output "workload_placement_command" {
  value       = local.outputs.workload_placement_command.value
  description = "Both Deployments should be entirely on Karpenter nodes, not on the managed node group. A Pending pod means its nodeSelector matched no pool, and Karpenter does not provision for a label no pool applies"
}
output "interruption_queue_name" {
  value       = local.outputs.interruption_queue_name.value
  description = "The queue EventBridge delivers interruption notices to and Karpenter polls. This pairing is what the spot experiment exercises: without it Karpenter learns a node is gone only once it stops responding, and by then the pods went with it"
}
output "interruption_queue_depth_command" {
  value       = local.outputs.interruption_queue_depth_command.value
  description = "Normally zero, because Karpenter deletes each message as it acts on it. A number that stays above zero means the controller is not polling - usually a wrong settings.interruptionQueue or missing SQS permissions, neither of which produces an error anywhere"
}
output "node_termination_handler_status_command" {
  value       = local.outputs.node_termination_handler_status_command.value
  description = "Covers the managed node group, which Karpenter does not manage and would not replace. desired and ready should match the node count - a node without a handler pod is a node that will vanish without being drained"
}
output "experiment_target_tags" {
  value       = local.outputs.experiment_target_tags.value
  description = "The Name tag each experiment searches for, next to the tag the pool actually applies. These come from the same value, so they cannot disagree - shown because a mismatch is the failure this project is most likely to hit and the only symptom is an experiment that fails on empty target resolution"
}
output "spot_interruption_start_command" {
  value       = local.outputs.spot_interruption_start_command.value
  description = "Sends the real two-minute warning to one spot instance. Karpenter picks it up from the queue, launches a replacement and drains the old node - watch the node view, not this command's output. Not started by the apply, because starting an experiment takes a node away and costs money"
}
output "stop_instance_start_command" {
  value       = local.outputs.stop_instance_start_command.value
  description = "The harsher half, and the one spot_instance_interruptions leaves out. EC2 issues no warning for an instance it is told to stop, so Karpenter's only signal is the instance state change event - the pods go away with the node and come back on a replacement rather than being drained ahead of it"
}
output "experiment_list_command" {
  value       = local.outputs.experiment_list_command.value
  description = "Every run with its final state. failed against a template whose targets look right is almost always empty target resolution: the tag matched no instance, which the configuration deliberately treats as a failure rather than a success against nothing"
}
output "experiment_detail_command" {
  value       = local.outputs.experiment_detail_command.value
  description = "Substitute an ID from the list above. The Targets section names the instance the experiment resolved to, which is the only record of whether the Name tag found what was intended"
}
output "experiment_log_command" {
  value       = local.outputs.experiment_log_command.value
  description = "FIS delivers a per-experiment log to this group, which the _monolithic template had no equivalent of - it recorded only a final state. Empty right after an apply, because no experiment has run yet"
}
output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "User data already ran this, so kubectl works out of the box. Re-run it if the kubeconfig is ever lost"
}
