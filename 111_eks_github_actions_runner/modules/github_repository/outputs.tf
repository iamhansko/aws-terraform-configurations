output "repository_url" {
  value       = github_repository.repository.html_url
  description = "The repository's URL, which is exactly what the runner scale set's githubConfigUrl has to be. Taken from the resource rather than rebuilt from owner and name by the caller, so the scale set cannot register against a URL the repository does not have (rules.md B-5)"
}
output "full_name" {
  value       = github_repository.repository.full_name
  description = "owner/name, the form the GitHub API and the gh CLI take"
}
output "workflow_branch" {
  value       = var.workflow_content == null ? null : github_repository_file.workflow[0].branch
  description = "Branch the workflow was committed to, read back from the file resource rather than from the repository's deprecated default_branch attribute - so it names the branch the file actually landed on. Null when no workflow was seeded"
}
output "actions_url" {
  value       = "${github_repository.repository.html_url}/actions"
  description = "The Actions tab. This is where the seeded workflow is run from and where its log is read"
}
output "workflow_path" {
  value       = var.workflow_content == null ? null : var.workflow_path
  description = "Path of the seeded workflow, or null when none was seeded. Re-exposed so the caller's instructions name the file that actually exists (rules.md B-5)"
}
output "visibility" {
  value       = github_repository.repository.visibility
  description = "Whether the repository is private. Surfaced because this is a deliberate deviation from the _monolithic template, which created it public - and because a public repository with self-hosted runners lets a pull request from a fork run code on a runner pod in this VPC"
}
output "archive_on_destroy" {
  value       = var.archive_on_destroy
  description = "Whether destroy archives the repository instead of deleting it. False means terraform destroy deletes it and its history - the one destructive thing in this project that is not an AWS resource (rules.md B-5)"
}
