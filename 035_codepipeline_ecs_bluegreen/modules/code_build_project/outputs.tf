output "project_name" {
  value       = aws_codebuild_project.code_build.name
  description = "Name of the build project, which the pipeline's build action names"
}
output "project_arn" {
  value       = aws_codebuild_project.code_build.arn
  description = "ARN of the build project. The pipeline role's codebuild statement is scoped to this rather than to every project in the account"
}
output "role_arn" {
  value       = aws_iam_role.code_build_iam_role.arn
  description = "ARN of the CodeBuild service role"
}
output "role_name" {
  value       = aws_iam_role.code_build_iam_role.name
  description = "Generated name of the CodeBuild service role"
}
output "log_group_name" {
  value       = "/aws/codebuild/${aws_codebuild_project.code_build.name}"
  description = "Log group CodeBuild writes build output to, which is the group the role's log statement is scoped to and the only place a build failure is explained"
}
output "build_log_command" {
  value       = "aws logs tail /aws/codebuild/${aws_codebuild_project.code_build.name} --since 1h --format short"
  description = "Command tailing the build log. A build that fails on docker build is privileged_mode, one that fails on docker push is the ECR statement, and one that fails on register-task-definition is the PassRole condition - none of those are visible anywhere else"
}
output "build_status_command" {
  value       = "aws codebuild list-builds-for-project --project-name ${aws_codebuild_project.code_build.name} --max-items 5 --query ids --output text | xargs -r aws codebuild batch-get-builds --ids --query 'builds[].[id,buildStatus,currentPhase,phases[?phaseStatus==`FAILED`].phaseType|[0]]' --output table"
  description = "Command listing recent builds with the phase that failed, which narrows a failure to pre_build, build or post_build before reading the log"
}
