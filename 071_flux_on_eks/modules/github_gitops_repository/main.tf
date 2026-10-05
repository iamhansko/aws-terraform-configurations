# A GitOps repository in the caller's own GitHub account, for Flux to reconcile.
#
# This is the half the _monolithic template reached with "flux bootstrap github", and it is still
# not that: bootstrapping also commits Flux's own manifests and points Flux at them, so Flux
# manages itself. Here the controllers stay installed by the chart in modules/flux, and what this
# adds is a repository Flux watches - created by Terraform rather than by hand, so it is in state
# and appears in a plan.
#
# What is deliberately not here: the GitRepository, the Kustomization and the Secret that lets the
# source controller clone a private repository. Those are Kubernetes objects and belong to the
# module that already makes them, which is pointed at this repository's outputs by the root
# (rules.md C-1). This module only talks to GitHub, which is why its providers.tf names github and
# nothing else.
resource "github_repository" "gitops" {
  name        = var.name
  description = var.description
  visibility  = var.visibility

  # Without this the repository is created with no commits and therefore no branch, and every file
  # resource below fails on a reference that does not exist. The variable's validation pins it
  # true for that reason.
  auto_init = var.auto_init

  # Archived rather than deleted on destroy unless told otherwise. The provider deletes a
  # repository permanently and GitHub does not undo it, so the default here is the recoverable one.
  archive_on_destroy = var.archive_on_destroy
}
# The manifests Flux finds when it first looks. A Kustomization pointed at an empty directory does
# not wait - it fails, with "kustomization.yaml not found", which reads like a wrong path.
#
# The branch is the repository's own rather than a value this module asks for.
#
# auto_init names the first branch from the account's default-branch setting - "main" for accounts
# created in the last few years, "master" for older ones - and the provider no longer accepts a
# default_branch argument to override it with. Asking for a specific name would mean creating that
# branch first, and only when it does not already exist: a condition on an apply-time value, which
# fails the plan outright rather than at apply (rules.md B-8). Following the repository cannot be
# wrong, and the name it settled on is an output (rules.md B-5).
#
# Through a data source rather than github_repository.gitops.default_branch, which is the same
# value: the provider deprecated that attribute on the resource, because setting it there no longer
# works. Reading it here is the supported form and keeps the plan free of deprecation warnings.
data "github_repository" "gitops" {
  full_name = github_repository.gitops.full_name
}
resource "github_repository_file" "seed" {
  for_each = var.seed_manifests

  repository = github_repository.gitops.name
  branch     = data.github_repository.gitops.default_branch
  file       = "${var.path}/${each.key}"
  content    = each.value

  commit_message = var.commit_message
  # auto_init already committed a README, and a re-run should write over whatever is there rather
  # than failing because the path is taken.
  overwrite_on_create = true

  lifecycle {
    # Seeded once, then left alone. The point of the repository is that a human edits it and Flux
    # applies the result, and without this every subsequent plan would propose reverting those
    # edits to the content in this configuration - Terraform and Flux would be fighting over the
    # same file through two different paths.
    #
    # Whole-attribute rather than scoped, and that is correct here for the same reason as the
    # one-shot rollout trigger in rules.md E-4: the intent is to write the file once, not to track
    # part of it. Changing the seed content in Terraform therefore does not reach the repository -
    # edit it in Git, which is where it now lives.
    ignore_changes = [content]
  }
}
