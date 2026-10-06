# Every output is a projection of local.outputs in main.tf, which is also what the
# README written onto the VS Code instance is rendered from (rules.md H-2). No value
# expression is written here: an output that built its own value would be missing from
# that README, and the apply would succeed either way. Whether this pattern still holds
# is checked by counting - the number of output blocks here must equal the number of
# entries in local.outputs.
#
# description is the one thing repeated, because Terraform rejects an expression there
# ("Variables not allowed") - it has to be a literal.
output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "URL of the code-server web UI, served through CloudFront"
}
output "cluster_name" {
  value       = local.outputs.cluster_name.value
  description = "Name of the EKS cluster"
}
output "alb_url" {
  value       = local.outputs.alb_url.value
  description = "HTTP URL of the internal load balancer the Rollout switches traffic on"
}
output "target_group_arn" {
  value       = local.outputs.target_group_arn.value
  description = "ARN of the active target group the Rollout's TargetGroupBinding names"
}
output "argo_rollouts_status_command" {
  value       = local.outputs.argo_rollouts_status_command.value
  description = "Command confirming the Argo Rollouts controller is Available"
}
output "rollout_watch_command" {
  value       = local.outputs.rollout_watch_command.value
  description = "Command following the Rollout's active and preview ReplicaSets"
}
output "target_health_command" {
  value       = local.outputs.target_health_command.value
  description = "Command listing which pod IPs are registered in the target group"
}
output "new_version_command" {
  value       = local.outputs.new_version_command.value
  description = "Command changing the image, which starts a blue/green rollout"
}
output "preview_check_command" {
  value       = local.outputs.preview_check_command.value
  description = "Command reaching the new version through the preview Service before promotion"
}
output "promote_command" {
  value       = local.outputs.promote_command.value
  description = "Command promoting the preview version to active"
}
output "argo_rollouts_dashboard_command" {
  value       = local.outputs.argo_rollouts_dashboard_command.value
  description = "Command serving the Argo Rollouts dashboard on the bastion"
}
output "rollouts_versions" {
  value       = local.outputs.rollouts_versions.value
  description = "The kubectl-argo-rollouts plugin version on the workbench and the controller version the chart installed, which should match"
}
output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "Command that points kubectl on the VS Code instance at the cluster"
}
