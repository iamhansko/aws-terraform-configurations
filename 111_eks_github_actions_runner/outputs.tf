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
output "cluster_name" {
  value       = local.outputs.cluster_name.value
  description = "Name of the EKS cluster the runners run in"
}
output "github_target" {
  value       = local.outputs.github_target.value
  description = "What the runners registered with. Created by this root - the resource the CloudFormation conversion dropped"
}
output "pipeline_test_procedure" {
  value       = local.outputs.pipeline_test_procedure.value
  description = "1. How to run the pipeline and watch a runner pod serve the job"
}
output "workflow_snippet" {
  value       = local.outputs.workflow_snippet.value
  description = "2. What makes any workflow land on these runners. runs-on has to match the scale set name exactly"
}
output "runner_scale_set_command" {
  value       = local.outputs.runner_scale_set_command.value
  description = "3. The scale set, the ephemeral runner set it manages, and any runner pods"
}
output "listener_command" {
  value       = local.outputs.listener_command.value
  description = "4. The listener, which runs in the controller's namespace rather than the runners'"
}
output "watch_runners_command" {
  value       = local.outputs.watch_runners_command.value
  description = "5. Watches a runner pod appear for a job and disappear afterwards"
}
output "listener_logs_command" {
  value       = local.outputs.listener_logs_command.value
  description = "6. The listener's log, which records each job assignment from GitHub"
}
output "controller_logs_command" {
  value       = local.outputs.controller_logs_command.value
  description = "7. The controller's log, where a 401, 403 or 404 from GitHub appears"
}
output "scaling_bounds" {
  value       = local.outputs.scaling_bounds.value
  description = "What ARC will ask for, and what the unscaled node group can actually provide"
}
output "repository_lifecycle" {
  value       = local.outputs.repository_lifecycle.value
  description = "The repository's visibility, and the fact that destroying this root deletes it outside AWS"
}
output "arc_version" {
  value       = local.outputs.arc_version.value
  description = "Version both ARC charts were installed at, pinned"
}
output "token_handling" {
  value       = local.outputs.token_handling.value
  description = "Where the GitHub token lives - a Kubernetes Secret rather than a helm command line"
}
output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "Re-points kubectl at the cluster. User data already ran this"
}
output "private_key_command" {
  value       = local.outputs.private_key_command.value
  description = "Reads the workbench's SSH private key out of SSM Parameter Store"
}
