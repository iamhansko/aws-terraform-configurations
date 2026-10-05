output "repository_name" {
  value       = aws_codecommit_repository.app.repository_name
  description = "Name of the repository, which the source stage's RepositoryName names and the pipeline role's permissions are scoped to (rules.md B-5)"
}
output "repository_arn" {
  value       = aws_codecommit_repository.app.arn
  description = "ARN of the repository, for the pipeline role's policy and for the EventBridge rule's resources pattern"
}
output "repository_id" {
  value       = aws_codecommit_repository.app.repository_id
  description = "CodeCommit's own identifier for the repository, distinct from its name"
}
output "clone_url_http" {
  value       = aws_codecommit_repository.app.clone_url_http
  description = "HTTPS clone URL. The workbench pushes to this with the AWS CLI credential helper, so the instance role is the credential and no token or key is stored anywhere"
}
output "branch_name" {
  value       = var.branch_name
  description = "Branch the pipeline reads, re-exposed so the local branch the workbench creates, the source stage and the EventBridge rule's referenceName all read one value (rules.md B-5)"
}
output "console_url" {
  value       = "https://${data.aws_region.current.region}.console.aws.amazon.com/codesuite/codecommit/repositories/${aws_codecommit_repository.app.repository_name}/browse?region=${data.aws_region.current.region}"
  description = "Where to read the repository in the console"
}
output "commit_log_command" {
  value       = "aws codecommit get-branch --repository-name ${aws_codecommit_repository.app.repository_name} --branch-name ${var.branch_name} --query 'branch.commitId' --output text"
  description = "The commit the branch points at. An error here saying the branch does not exist means the workbench's push has not happened yet, which is also why the pipeline would not have started"
}
output "credential_helper_config" {
  value       = "git config --local credential.helper '!aws codecommit credential-helper $@' && git config --local credential.UseHttpPath true"
  description = "What makes git authenticate to CodeCommit as the caller's IAM identity. Re-exposed because it is the whole of the credential story here: on the workbench that identity is the instance role, so nothing is stored on disk"
}
