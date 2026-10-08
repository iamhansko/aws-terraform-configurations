variable "name" {
  type        = string
  description = "Repository name. The runners register against https://github.com/<owner>/<name>, and the owner comes from the provider configuration in the root rather than from a variable here"

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]{1,100}$", var.name))
    error_message = "name must be 1-100 characters of letters, digits, underscores, dots and hyphens."
  }
}
variable "description" {
  type        = string
  default     = "Workflows here run on ephemeral self-hosted runners in an EKS cluster, created by Terraform"
  description = "Repository description. Free text: this one goes to the GitHub API, which has no character restrictions of the kind EC2 puts on a security group description (rules.md F-1)"
}
variable "visibility" {
  type        = string
  default     = "private"
  description = <<-DESC
    Repository visibility.

    Private, where the _monolithic template set IsPrivate: false. This is a deliberate deviation from what the
    original did, and the reason is the thing this project builds: a public repository with self-hosted runners
    lets anyone open a pull request from a fork and have their code executed on a runner pod inside this VPC,
    with that pod's network access and whatever the node's instance profile grants. GitHub's own hardening
    guide says not to use self-hosted runners with public repositories.

    Set to "public" to match the original exactly, with that understood.
  DESC

  validation {
    condition     = contains(["private", "public", "internal"], var.visibility)
    error_message = "visibility must be private, public or internal (internal needs an organisation on a GitHub Enterprise plan)."
  }
}
variable "enable_issues" {
  type        = bool
  default     = true
  description = "Whether the issues tab is on, true as the _monolithic template's EnableIssues had it"
}
variable "auto_init" {
  type        = bool
  default     = true
  description = <<-DESC
    Whether GitHub writes an initial commit, which is what gives the repository a default branch.

    True, and effectively required: a repository with no commits has no branch, so there is nowhere to put the
    workflow file below, and the Actions tab has nothing to offer. CodeStar seeded the repository from an S3
    object instead, which is the same idea by a different route.
  DESC
}
variable "workflow_path" {
  type        = string
  default     = ".github/workflows/arc-demo.yml"
  description = "Path the seeded workflow is written to. GitHub only looks for workflows under .github/workflows, so a path outside it produces a repository that looks correct and never runs anything"

  validation {
    condition     = var.workflow_path == null || can(regex("^\\.github/workflows/[A-Za-z0-9_.-]+\\.ya?ml$", var.workflow_path))
    error_message = "workflow_path must be a .yml or .yaml file under .github/workflows/ - GitHub does not look anywhere else."
  }
}
variable "workflow_content" {
  type        = string
  default     = null
  description = <<-DESC
    Contents of the workflow to seed, or null to create the repository empty.

    Seeded rather than left to the operator because of what it is for: this is the only thing that makes the
    runners do anything, and its "runs-on" has to match the runner scale set's name exactly. A workflow naming
    anything else queues forever and reports nothing, which is the most common way this setup appears broken -
    so the value is built in the root from the same variable the scale set is named from (rules.md B-4/B-5).
  DESC

  validation {
    condition     = var.workflow_content == null || can(regex("runs-on:", var.workflow_content))
    error_message = "workflow_content must contain a runs-on: line, or the workflow has no runner to land on."
  }
}
variable "workflow_commit_message" {
  type        = string
  default     = "Add a workflow that runs on the EKS runner scale set"
  description = "Commit message for the seeded workflow. It appears in the repository history as the first commit after the initial one"
}
variable "archive_on_destroy" {
  type        = bool
  default     = false
  description = <<-DESC
    Whether terraform destroy archives this repository instead of deleting it.

    False, which means destroy deletes the repository and everything in it. That matches the original - deleting
    a CloudFormation stack containing an AWS::CodeStar::GitHubRepository deleted the repository too - and it is
    the only value that lets this project be applied again under the same name, because an archived repository
    still holds its name.

    It is also the one destructive thing in this root that is not an AWS resource, so it is surfaced as an
    output rather than left to be discovered.
  DESC
}
