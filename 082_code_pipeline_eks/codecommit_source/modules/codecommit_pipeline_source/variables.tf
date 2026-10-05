variable "repository_name" {
  type        = string
  default     = "fastapi-sample"
  description = "Name of the CodeCommit repository the pipeline reads, keeping the name the _monolithic template gave its GitHub repository. Unique per account and region, so two copies of this project in one account need different values - the caller derives it from the project name"

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]{1,100}$", var.repository_name))
    error_message = "repository_name must be 1-100 characters of letters, digits, dots, underscores and hyphens, which is what CodeCommit accepts."
  }
}
variable "repository_description" {
  type        = string
  default     = "Sample FastAPI application deployed to EKS by CodePipeline"
  description = "Description set on the repository"

  validation {
    condition     = length(var.repository_description) <= 1000
    error_message = "repository_description must be 1000 characters or fewer, which is CodeCommit's limit."
  }
}
variable "branch_name" {
  type        = string
  default     = "main"
  description = <<-DESC
    Branch the pipeline's source stage reads, and the branch the workbench creates and pushes.

    This module's to choose: CodeCommit adopts the first branch pushed as the repository's default, and
    that push is made by this project with "git init -b <branch>". So one value feeds the local branch, the
    source stage and the EventBridge rule's referenceName, and the output below is where all three read it
    from (rules.md B-5).

    Main rather than the _monolithic template's master, because that is what git now creates by default.
  DESC

  validation {
    condition     = can(regex("^[A-Za-z0-9._/-]{1,255}$", var.branch_name))
    error_message = "branch_name must be a plain git branch name."
  }
}
