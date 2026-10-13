# Every value is projected from local.outputs in main.tf, which also renders the workbench README
# (rules.md B-5/H-2). Descriptions remain literals because Terraform does not allow expressions there.

output "apply_order" {
  value       = local.outputs.apply_order.value
  description = "Required target-then-source apply order across the two independent states."
}

output "destroy_order" {
  value       = local.outputs.destroy_order.value
  description = "Required source-then-target destroy order across the two independent states."
}

output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "Direct URL of the source-account code-server workbench."
}

output "source_region" {
  value       = local.outputs.source_region.value
  description = "Region containing source-account replication resources."
}

output "source_repository" {
  value       = local.outputs.source_repository.value
  description = "Name of the source CodeCommit repository."
}

output "source_clone_command" {
  value       = local.outputs.source_clone_command.value
  description = "Workbench command to clone the source repository with git-remote-codecommit."
}

output "target_region" {
  value       = local.outputs.target_region.value
  description = "Region containing the target CodeCommit repository."
}

output "target_repository" {
  value       = local.outputs.target_repository.value
  description = "Name of the target CodeCommit repository."
}

output "source_codebuild_role_arn" {
  value       = local.outputs.source_codebuild_role_arn.value
  description = "ARN of the fixed source CodeBuild role trusted by the target account."
}

output "target_cross_account_role_arn" {
  value       = local.outputs.target_cross_account_role_arn.value
  description = "ARN of the target role assumed during replication."
}

output "pipeline_name" {
  value       = local.outputs.pipeline_name.value
  description = "Name of the replication CodePipeline pipeline."
}

output "pipeline_status_command" {
  value       = local.outputs.pipeline_status_command.value
  description = "Command to inspect the replication pipeline state."
}

output "build_project_name" {
  value       = local.outputs.build_project_name.value
  description = "Name of the Git mirror CodeBuild project."
}

output "build_status_command" {
  value       = local.outputs.build_status_command.value
  description = "Command to inspect the latest mirror build."
}

output "source_head_command" {
  value       = local.outputs.source_head_command.value
  description = "Command to read the source main commit ID."
}

output "target_repository_verification_command" {
  value       = local.outputs.target_repository_verification_command.value
  description = "Target-credential command to inspect the target repository."
}

output "target_head_command" {
  value       = local.outputs.target_head_command.value
  description = "Target-credential command to read the mirrored main commit ID."
}

output "artifact_bucket_name" {
  value       = local.outputs.artifact_bucket_name.value
  description = "Generated private pipeline artifact bucket name."
}

output "vscode_port_forward_command" {
  value       = local.outputs.vscode_port_forward_command.value
  description = "Optional Session Manager command that forwards code-server to localhost without using an inbound rule."
}

output "private_key_command" {
  value       = local.outputs.private_key_command.value
  description = "Command to retrieve the generated workbench private key from Parameter Store."
}
