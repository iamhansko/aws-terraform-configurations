output "project_name" {
  value       = aws_codebuild_project.runner.name
  description = "Name of the CodeBuild project"
}
output "project_arn" {
  value       = aws_codebuild_project.runner.arn
  description = "ARN of the CodeBuild project"
}
# The runs-on label the workflow has to carry, assembled here rather than in the workflow template.
#
# GitHub matches a queued job to this project by the label, so the two have to agree character for
# character; building it once from the project's own name is what makes that structural rather than
# something to remember (rules.md B-5). The workflow appends the run id and run attempt.
output "runner_label_prefix" {
  value       = "codebuild-${aws_codebuild_project.runner.name}"
  description = "Prefix of the workflow's runs-on label. The workflow appends -<run id>-<run attempt>"
}
output "workflow_name" {
  value       = var.workflow_name
  description = "Workflow the webhook filters on, re-exposed so the generated workflow's name field and this filter come from one value (rules.md B-5)"
}
output "service_role_arn" {
  value       = aws_iam_role.code_build_iam_role.arn
  description = "ARN of the build's IAM role"
}
output "service_role_name" {
  value       = aws_iam_role.code_build_iam_role.name
  description = "Name of the build's IAM role, for attaching extra policies from the root module"
}
output "webhook_url" {
  value       = aws_codebuild_webhook.runner.url
  description = "The webhook endpoint CodeBuild registered on the repository. Its presence is how to tell the trigger exists - the _monolithic template's Triggers property was dropped in conversion, and a project without it never starts a build"
}
output "build_log_group_name" {
  value       = "/aws/codebuild/${aws_codebuild_project.runner.name}"
  description = "CloudWatch log group the builds write to, which is also the group the role's Logs statement is scoped to"
}
output "list_builds_command" {
  value       = "aws codebuild list-builds-for-project --project-name ${aws_codebuild_project.runner.name} --query ids --output table"
  description = "Every build this project has run, newest first. Empty while a GitHub job sits queued means the webhook never fired or its label does not match runner_label_prefix"
}
output "tail_build_log_command" {
  value       = "aws logs tail /aws/codebuild/${aws_codebuild_project.runner.name} --follow"
  description = "Live build output. This is where the workflow's docker build, render and deploy steps report, and where a scoped-down role shows up as an AccessDenied naming the call it was missing"
}
