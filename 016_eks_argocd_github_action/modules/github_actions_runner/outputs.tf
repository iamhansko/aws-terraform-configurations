output "project_name" {
  value       = aws_codebuild_project.runner.name
  description = "Name of the CodeBuild project, read from the resource rather than echoing the variable (rules.md B-5)"
}
output "project_arn" {
  value       = aws_codebuild_project.runner.arn
  description = "ARN of the CodeBuild project"
}
output "service_role_arn" {
  value       = aws_iam_role.codebuild.arn
  description = "ARN of the role the build assumes"
}
output "webhook_url" {
  value       = aws_codebuild_webhook.runner.payload_url
  description = "Payload URL CodeBuild registered with GitHub. Its presence is how to tell the webhook was created - the _monolithic conversion left this resource out entirely, so builds were never triggered"
}
output "builds_command" {
  value       = "aws codebuild list-builds-for-project --project-name ${aws_codebuild_project.runner.name} --query 'ids' --output table"
  description = "Command listing builds. Empty after a workflow run means the webhook filter did not match - check the workflow name (rules.md H-2)"
}
output "build_log_command" {
  value       = "aws logs tail /aws/codebuild/${aws_codebuild_project.runner.name} --follow"
  description = "Command tailing the runner's log group, which is where a failing docker build or ECR push shows up"
}
