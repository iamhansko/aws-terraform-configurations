# Every value here is a projection of local.outputs in main.tf, which the README written onto the VS Code
# instance renders from the same map - so no value expression exists twice, and an output cannot be added
# without also appearing in that README (rules.md B-5/H-2).
#
# description is the one thing that cannot be projected: Terraform rejects an expression in an output's
# description ("Variables not allowed"), so the wording is a literal on both sides.
output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "Open the IDE here. ~/src is the working copy the apply pushed to CodeCommit, remote and credential helper already configured"
}
output "application_url" {
  value       = local.outputs.application_url.value
  description = "The application, through the pre-created load balancer the controller adopted. It answers once the first pipeline execution has deployed, which the apply itself triggers"
}
output "cluster_name" {
  value       = local.outputs.cluster_name.value
  description = "Name of the EKS cluster the pipeline's deploy stage applies to"
}
output "pipeline" {
  value       = local.outputs.pipeline.value
  description = "The pipeline's four stages, the repository and branch it reads, and whether a push starts a run"
}
output "source_repository" {
  value       = local.outputs.source_repository.value
  description = "The CodeCommit repository the pipeline reads, its clone URL and its branch. Created and pushed to by this configuration"
}
output "no_manual_setup" {
  value       = local.outputs.no_manual_setup.value
  description = "There is none. The repository, the first commit, the trigger and the first execution all happen inside terraform apply"
}
output "first_commit_command" {
  value       = local.outputs.first_commit_command.value
  description = "The commit the apply pushed. A missing branch means the push did not happen, which is also why no run started"
}
output "trigger_check_command" {
  value       = local.outputs.trigger_check_command.value
  description = "1. Whether the EventBridge rule failed to start the pipeline. That failure appears nowhere else"
}
output "pipeline_state_command" {
  value       = local.outputs.pipeline_state_command.value
  description = "2. Every stage and how its last run ended"
}
output "build_log_command" {
  value       = local.outputs.build_log_command.value
  description = "3. The build log, which prints the manifest the build stage rendered"
}
output "workload_command" {
  value       = local.outputs.workload_command.value
  description = "4. What the pipeline deployed into the cluster"
}
output "provenance_command" {
  value       = local.outputs.provenance_command.value
  description = "5. Which build and which execution produced the running Deployment"
}
output "repush_command" {
  value       = local.outputs.repush_command.value
  description = "6. Commits and pushes a change from the workbench, which is the source event that starts a run"
}
output "image_list_command" {
  value       = local.outputs.image_list_command.value
  description = "7. The images in the registry, oldest first"
}
output "adopted_load_balancer_check_command" {
  value       = local.outputs.adopted_load_balancer_check_command.value
  description = "8. Lists every load balancer tagged for this cluster. One is correct; two means adoption failed silently"
}
output "manual_execution_command" {
  value       = local.outputs.manual_execution_command.value
  description = "9. Starts the pipeline without a push, which separates a trigger problem from a build or deploy one"
}
output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "Re-points kubectl at the cluster. User data already ran this"
}
