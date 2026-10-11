output "project_name" {
  value       = aws_codebuild_project.build.name
  description = "Name of the CodeBuild project"
}
output "project_arn" {
  value       = aws_codebuild_project.build.arn
  description = "ARN of the CodeBuild project, for scoping whatever starts it"
}
output "build_revision" {
  value       = sha256(join("\n", [var.buildspec, var.model_tier, var.models_bucket_name]))
  description = "Hash of what the build does. Handed to the trigger so a changed model list or tier starts a new download on the next apply, rather than updating the project and downloading nothing (rules.md B-5)"
}
output "build_status_command" {
  value       = "aws codebuild batch-get-builds --ids $(aws codebuild list-builds-for-project --project-name ${aws_codebuild_project.build.name} --max-items 1 --query 'ids[0]' --output text) --query 'builds[0].{Status:buildStatus,Phase:currentPhase,Started:startTime}' --output table"
  description = "Status of the most recent model download"
}
output "start_build_command" {
  value       = "aws codebuild start-build --project-name ${aws_codebuild_project.build.name} --query 'build.id' --output text"
  description = "Starts the download again by hand. Files already in the bucket are skipped"
}
