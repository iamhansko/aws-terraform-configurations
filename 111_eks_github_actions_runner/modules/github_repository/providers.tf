terraform {
  required_version = ">= 1.9"
  required_providers {
    # The provider the conversion note pointed at. The _monolithic template created this repository with
    # AWS::CodeStar::GitHubRepository - a legacy type the AWS provider has no equivalent for - and cfn2tf left
    # it as a comment reading "Legacy CodeStar resource; the AWS provider has no equivalent. Use the GitHub
    # provider." Nothing picked that up, so the repository the runners register with was never created.
    github = { source = "integrations/github", version = "~> 6.0" }
  }
}
# No provider block here: a module declares what it needs and the root configures it (rules.md A-2). The owner
# and the token live in the root's provider "github" block.
