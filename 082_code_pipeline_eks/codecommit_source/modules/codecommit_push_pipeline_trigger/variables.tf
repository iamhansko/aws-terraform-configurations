variable "name" {
  type        = string
  description = "Base name for the rule and the role. No default: the caller derives it from the project name, because an EventBridge rule name is unique per account and region"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9_.-]{1,40}$", var.name))
    error_message = "name must be 2-41 characters of letters, digits, underscores, dots and hyphens, short enough that the \"-codecommit-push\" suffix stays inside the 64 character rule name limit."
  }
}
variable "repository_arn" {
  type        = string
  description = "ARN of the repository the rule watches, used in the event pattern's resources so a push to a different repository in this account does not start the pipeline"

  validation {
    condition     = can(regex("^arn:aws:codecommit:", var.repository_arn))
    error_message = "repository_arn must be a CodeCommit repository ARN."
  }
}
variable "repository_name" {
  type        = string
  description = "Name of the repository, used only in the rule's description so the console says what it watches"

  validation {
    condition     = length(var.repository_name) > 0
    error_message = "repository_name must not be empty."
  }
}
variable "branch_name" {
  type        = string
  description = "Branch whose commits start the pipeline, matched against the event's referenceName. Comes from the source module so it cannot name a branch other than the one the source stage reads (rules.md B-5)"

  validation {
    condition     = can(regex("^[A-Za-z0-9._/-]{1,255}$", var.branch_name))
    error_message = "branch_name must be a plain git branch name."
  }
}
variable "pipeline_arn" {
  type        = string
  description = "ARN of the pipeline to start, which the role's policy is also scoped to"

  validation {
    condition     = can(regex("^arn:aws:codepipeline:", var.pipeline_arn))
    error_message = "pipeline_arn must be a CodePipeline ARN."
  }
}
variable "pipeline_name" {
  type        = string
  description = "Name of the pipeline, used as the target id and in the rule's description"

  validation {
    condition     = length(var.pipeline_name) > 0
    error_message = "pipeline_name must not be empty."
  }
}
variable "enabled" {
  type        = bool
  default     = true
  description = "Whether a push starts the pipeline automatically. True, which is the finished state: the source stage sets PollForSourceChanges to false, so this rule is the only thing that starts a run and without it a push changes nothing. Set false to see exactly that (rules.md B-4)"
}
