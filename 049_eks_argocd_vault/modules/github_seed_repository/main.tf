# The Git repository Argo CD syncs from, and the manifests in it.
#
# Why this exists: nothing created it before, and the demo cannot work without it. Argo CD is pointed
# at https://github.com/<user>/<repo>.git, and the application this project exists to demonstrate -
# the Vault plugin substituting <path:kv/data/admin#user> at sync time - has nowhere to read
# manifests from until that repository holds them.
#
# What was there instead: the _monolithic template wrote the same manifests onto the bastion, zipped
# them and uploaded the zip to an S3 bucket that nothing consumed, and left the "argocd app create"
# call commented out in a script on disk. So the repository was an unstated prerequisite the operator
# had to create and populate by hand, and following the template exactly produced an Argo CD with an
# application pointing at a 404. Declaring it here makes the prerequisite part of the configuration.
#
# Declared as provider resources rather than as git commands in the SSM association that writes the
# same files onto the instance: the repository and its contents end up in state, a plan shows a
# manifest change before it is pushed, and the token never travels through a shell (rules.md E-1).
#
# Note what destroy does. delete_repo is in the token's scopes, so terraform destroy removes the
# repository and everything in it. That is the right lifecycle for a demo repository this
# configuration created, and it is worth knowing before pointing these variables at a repository
# that already holds anything.
resource "github_repository" "seed" {
  name        = var.repository_name
  description = var.repository_description
  visibility  = var.visibility

  # An empty repository has no default branch, and github_repository_file needs one to commit
  # against. auto_init makes the initial commit so the files below have somewhere to land.
  auto_init = true

  # The repository is a manifest source, so none of GitHub's collaboration surface applies.
  # has_downloads is not in the list: the provider marks it deprecated because GitHub retired the
  # feature behind it.
  has_issues   = false
  has_wiki     = false
  has_projects = false
}
# One commit per manifest. for_each over a map whose keys are repository paths, so adding a manifest
# in the caller's locals adds a file here without touching this module (rules.md B-7). The keys are
# literal strings from configuration, known at plan time, which is what lets them be for_each keys
# (rules.md B-8).
resource "github_repository_file" "manifest" {
  for_each = var.files

  repository = github_repository.seed.name
  # branch is deliberately not set. It is optional and computed, so the provider commits to the
  # repository's default branch - whatever auto_init created - and then reports it back, which the
  # module's default_branch output reads. Naming it here would mean either hardcoding "main", which
  # is only GitHub's current default for new accounts, or reading
  # github_repository.seed.default_branch, which the provider has deprecated.
  file                = each.key
  content             = each.value
  commit_message      = "${var.commit_message_prefix} ${each.key}"
  commit_author       = var.commit_author
  commit_email        = var.commit_email
  overwrite_on_create = true
}
