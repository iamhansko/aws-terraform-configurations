output "repository_name" {
  value       = github_repository.seed.name
  description = "Name of the created repository"
}
output "clone_url" {
  value       = github_repository.seed.http_clone_url
  description = "HTTPS clone URL, re-exposed so the caller's \"argocd app create\" command names the repository that was actually created instead of rebuilding the URL from the user and repo variables (rules.md B-5)"
}
output "html_url" {
  value       = github_repository.seed.html_url
  description = "Browser URL of the repository, so the committed manifests can be checked without cloning"
}
output "default_branch" {
  # Read back from the files rather than from the repository, whose default_branch attribute the
  # provider deprecated. distinct collapses the one branch they all landed on and one() asserts that
  # there is exactly one, so a future change that splits the commits across branches fails here
  # instead of producing an output that quietly describes only some of them.
  value       = one(distinct([for f in github_repository_file.manifest : f.branch]))
  description = "Branch the manifests were committed to. Argo CD tracks the repository's default branch unless told otherwise, so a mismatch here is why an application can sync nothing while reporting no error"
}
output "committed_files" {
  value       = sort(keys(github_repository_file.manifest))
  description = "Paths committed to the repository. Worth surfacing: Argo CD is pointed at a path inside the repository, and an application stuck on \"directory contains no manifests\" is usually this list not containing what that path expects"
}
