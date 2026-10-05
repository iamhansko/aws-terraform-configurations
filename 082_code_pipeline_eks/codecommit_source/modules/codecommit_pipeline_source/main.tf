data "aws_region" "current" {}
# The repository the pipeline reads.
#
# This is where this variant departs from the _monolithic template, so it is recorded here rather than left
# to be rediscovered. That template's source was a GitHub repository read through a CodeStar connection, and
# a connection cannot be completed by an API call: AWS documents the handshake as a console action, and the
# operations the console uses for it are not in the CLI or the SDKs. So the original could not finish
# without somebody clicking through it, and its pipeline's source stage failed until they did.
#
# CodeCommit has no third party in it. The repository is in the same account as the pipeline, the source
# stage is authorised by an IAM policy, and the workbench pushes to it with the instance role - so nothing
# in this variant waits for a person.
#
# What the swap costs, stated plainly: CodeCommit is closed to accounts that had not used it before
# 25 July 2024. This variant only applies in an account that already has access, and nothing here can work
# around that - "aws codecommit create-repository" is the check, and it fails with an explicit message.
resource "aws_codecommit_repository" "app" {
  repository_name = var.repository_name
  description     = var.repository_description

  # default_branch is deliberately not set, and it is worth saying why rather than leaving it to look like
  # an omission: AWS can only make a branch the default once that branch exists, and a repository Terraform
  # has just created has no commits and therefore no branches. Setting it here fails.
  #
  # The first push creates the branch and CodeCommit adopts it as the repository's default, which is why
  # branch_name is this module's to choose and re-expose rather than something read back (rules.md B-5).
}
