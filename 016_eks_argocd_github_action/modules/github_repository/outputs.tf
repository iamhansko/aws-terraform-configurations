output "name" {
  value       = github_repository.app.name
  description = "Repository name, read from the resource rather than echoing the variable (rules.md B-5)"
}
output "full_name" {
  value       = github_repository.app.full_name
  description = "owner/name of the repository"
}
output "http_clone_url" {
  value       = github_repository.app.http_clone_url
  description = "https clone URL. This is what the Argo CD Application's repoURL takes, and what the CodeBuild project's source location points at"
}
output "html_url" {
  value       = github_repository.app.html_url
  description = "Browser URL of the repository"
}
output "default_branch" {
  value       = var.default_branch
  description = "Branch the workflow triggers on and Argo CD tracks. Taken from the variable rather than github_repository.default_branch, which the provider deprecated in favour of the separate github_branch_default resource"
}
output "manifest_path" {
  value       = var.manifest_path
  description = "Directory the workflow rewrites and Argo CD syncs, re-exposed so the caller passes one value to both sides instead of two that can drift (rules.md B-5)"
}
output "workflow_name" {
  value       = var.workflow_name
  description = "Workflow name, re-exposed because the CodeBuild webhook filters on it - a mismatch leaves builds untriggered with nothing logged anywhere"
}
output "edit_index_url" {
  value       = "${github_repository.app.html_url}/edit/${var.default_branch}/index.html"
  description = "Direct link to edit index.html in the browser, which is the action that starts the pipeline: the workflow triggers on a push touching that path (rules.md H-2)"
}
