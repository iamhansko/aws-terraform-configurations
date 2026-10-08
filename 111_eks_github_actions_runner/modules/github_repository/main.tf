# The repository the runner scale set registers against, and the workflow that exercises it.
#
# Both here because they are one thing: a repository with no workflow under .github/workflows gives the
# runners nothing to do, and a workflow file cannot exist before the repository has a branch to hold it
# (rules.md C-2).
#
# ---------------------------------------------------------------------------------------------------
# Why this module exists
# ---------------------------------------------------------------------------------------------------
#
# The _monolithic template created this repository with AWS::CodeStar::GitHubRepository, and cfn2tf could not
# convert it:
#
#   # === GitHubRepository (AWS::CodeStar::GitHubRepository) NOT CONVERTED ===
#   # Legacy CodeStar resource; the AWS provider has no equivalent. Use the GitHub provider.
#
# Two things followed from that, and only the second one was visible. The runner set's githubConfigUrl kept a
# literal "UNSUPPORTED_REF_GitHubRepository" where the reference had been, which was noticed and fixed. The
# repository itself was simply gone, and the modularised configuration recorded that as a documented gap -
# an output explaining that the repository is not created here.
#
# That is not what the original did, and the gap is not benign. Without the repository the controller cannot
# get a runner registration token, so it never creates the listener, and the whole project does nothing:
#
#   POST https://api.github.com/repos/<owner>/<repo>/actions/runners/registration-token
#   failed(status="404 Not Found")
#
# Nothing in the apply reports it. helm's wait = true on the runner scale set release does not catch it either,
# for a reason worth knowing: that chart's only real object is the AutoscalingRunnerSet custom resource, and
# helm does not wait on custom resources - the listener is created afterwards by the controller, out of band.
# So the apply succeeds, every resource is green, and the failure lives in a controller log.
# ---------------------------------------------------------------------------------------------------
resource "github_repository" "repository" {
  name        = var.name
  description = var.description
  visibility  = var.visibility
  has_issues  = var.enable_issues
  # Gives the repository an initial commit and therefore a default branch, which the workflow file below needs
  # to exist at all.
  auto_init = var.auto_init
  # False archives rather than deletes on destroy, and an archived repository keeps its name - so a second
  # apply of this project would fail on the name being taken. Deleting matches the original (rules.md B-4).
  archive_on_destroy = var.archive_on_destroy
}
# The workflow, committed to the default branch.
#
# Optional, as a nullable variable rather than a flag, so a caller that wants an empty repository passes
# nothing and this module never learns that such a caller exists (rules.md B-4).
resource "github_repository_file" "workflow" {
  count = var.workflow_content == null ? 0 : 1

  repository = github_repository.repository.name
  # No branch argument. It is optional and computed, defaulting to the repository's default branch, which is
  # what auto_init just created - and the alternative of naming it from
  # github_repository.repository.default_branch reads an attribute the provider has deprecated, because a
  # repository's default branch is now something github_branch_default owns rather than something this
  # resource sets. Leaving it out means the branch is read back from this resource instead of asserted.
  file                = var.workflow_path
  content             = var.workflow_content
  commit_message      = var.workflow_commit_message
  overwrite_on_create = true
}
