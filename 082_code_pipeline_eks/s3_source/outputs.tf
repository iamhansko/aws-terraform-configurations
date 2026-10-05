# Every value here is a projection of local.outputs in main.tf, which the README written onto the VS Code
# instance renders from the same map - so no value expression exists twice, and an output cannot be added
# without also appearing in that README (rules.md B-5/H-2).
#
# description is the one thing that cannot be projected: Terraform rejects an expression in an output's
# description ("Variables not allowed"), so the wording is a literal on both sides.
output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "Open the IDE here. The application source is in ~/src, which the bootstrap packaged and uploaded"
}
output "application_url" {
  value       = local.outputs.application_url.value
  description = "The application, through the pre-created load balancer the controller adopted. It answers once a pipeline execution has deployed"
}
output "cluster_name" {
  value       = local.outputs.cluster_name.value
  description = "Name of the EKS cluster the pipeline's deploy stage applies to"
}
output "pipeline" {
  value       = local.outputs.pipeline.value
  description = "The pipeline's four stages and what starts it"
}
output "source_archive" {
  value       = local.outputs.source_archive.value
  description = "The S3 object the pipeline reads. Uploading a new one is the source event"
}
output "ecr_repository" {
  value       = local.outputs.ecr_repository.value
  description = "Where the image build stage pushes. Nothing watches it in this variant"
}
output "pipeline_state_command" {
  value       = local.outputs.pipeline_state_command.value
  description = "1. Every stage and how its last run ended"
}
output "build_log_command" {
  value       = local.outputs.build_log_command.value
  description = "2. The build log, which prints the manifest the build stage rendered"
}
output "workload_command" {
  value       = local.outputs.workload_command.value
  description = "3. What the pipeline deployed into the cluster"
}
output "provenance_command" {
  value       = local.outputs.provenance_command.value
  description = "4. Which build and which execution produced the running Deployment"
}
output "reupload_command" {
  value       = local.outputs.reupload_command.value
  description = "5. Repackages and uploads the application, which is the source event that starts a run"
}
output "archive_versions_command" {
  value       = local.outputs.archive_versions_command.value
  description = "6. Every version of the archive, which is the record of how often the pipeline was triggered"
}
output "image_list_command" {
  value       = local.outputs.image_list_command.value
  description = "7. The images in the registry, oldest first"
}
output "adopted_load_balancer_check_command" {
  value       = local.outputs.adopted_load_balancer_check_command.value
  description = "8. Lists every load balancer tagged for this cluster. One is correct; two means adoption failed silently"
}
output "trigger_failure_command" {
  value       = local.outputs.trigger_failure_command.value
  description = "9. Whether the EventBridge rule fired and failed to start the pipeline"
}
output "manual_execution_command" {
  value       = local.outputs.manual_execution_command.value
  description = "10. Starts the pipeline without an upload, which separates a source problem from a build or deploy one"
}
output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "Re-points kubectl at the cluster. User data already ran this"
}
