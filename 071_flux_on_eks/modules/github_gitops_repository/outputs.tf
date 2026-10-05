output "name" {
  value       = github_repository.gitops.name
  description = "Repository name, read back off the resource"
}
output "full_name" {
  value       = github_repository.gitops.full_name
  description = "The <owner>/<name> form. Read off the resource rather than built from a variable, so it names the account the token actually belongs to rather than one the caller believed it did"
}
output "html_url" {
  value       = github_repository.gitops.html_url
  description = "Browser URL for the repository, for the README the workbench renders"
}
output "clone_url" {
  value       = github_repository.gitops.http_clone_url
  description = "The https clone URL a GitRepository is pointed at. Over https rather than ssh because the credential that reaches it is a token, which is what the caller already has - ssh would mean generating and registering a deploy key as well"
}
output "branch" {
  value       = data.github_repository.gitops.default_branch
  description = "Default branch the repository was created with, read off the resource rather than taken from a variable. It is what the seeded files were committed to and what the caller points Flux at, so there is one value rather than two that have to agree (rules.md B-5)"
}
output "path" {
  value       = var.path
  description = "Directory the seeded manifests were written to, re-exposed so the caller's Kustomization and this module name one value (rules.md B-5)"
}
output "flux_path" {
  value       = "./${var.path}"
  description = "The same directory in the form Flux requires. A Kustomization's path has to be repository-relative and start with ./, so the conversion lives here rather than in the caller, where it would be a string concatenation that has to agree with path"
}
output "seeded_files" {
  value       = [for file in sort(keys(var.seed_manifests)) : "${var.path}/${file}"]
  description = "Files committed into the repository. These are what Flux applies on its first reconciliation, and what a human edits to make it apply something else"
}
output "edit_url_prefix" {
  value       = "${github_repository.gitops.html_url}/edit/${data.github_repository.gitops.default_branch}/${var.path}"
  description = "GitHub's edit URL for this directory, without a file name. A prefix rather than a finished link because this module does not know which of the seeded manifests matters to the caller - appending the file name there keeps the choice where the knowledge is (rules.md B-5). Editing a file through it and committing is the demo: the change reaches the cluster on the source controller's next poll, with no terraform apply involved"
}
