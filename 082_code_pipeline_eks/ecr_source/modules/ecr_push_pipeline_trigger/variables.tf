variable "name" {
  type        = string
  description = "Base name for the rule and its role"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9._-]{1,50}$", var.name))
    error_message = "name must be 2-51 characters of letters, digits, dots, underscores and hyphens."
  }
}
variable "repository_name" {
  type        = string
  description = "Repository whose pushes start the pipeline. Taken from the module that created it rather than restated: the event pattern matches on this exact string, and a pattern naming a repository that does not exist matches nothing and reports nothing (rules.md B-5)"

  validation {
    condition     = length(var.repository_name) > 0
    error_message = "repository_name must not be empty."
  }
}
variable "image_tag" {
  type        = string
  default     = "latest"
  description = "Tag whose pushes start the pipeline. Has to be the tag the pipeline's source stage watches - a rule triggering on one tag while the source reads another starts an execution that finds nothing new and succeeds without deploying (rules.md B-5)"

  validation {
    condition     = length(var.image_tag) > 0
    error_message = "image_tag must not be empty."
  }
}
variable "pipeline_arn" {
  type        = string
  description = "Pipeline this rule starts. Taken from the pipeline module, so the role's permission and the target cannot name different pipelines (rules.md B-5)"

  validation {
    condition     = can(regex("^arn:aws:codepipeline:", var.pipeline_arn))
    error_message = "pipeline_arn must be a CodePipeline ARN."
  }
}
variable "pipeline_name" {
  type        = string
  description = "Name of that pipeline, used as the rule target's identifier"

  validation {
    condition     = length(var.pipeline_name) > 0
    error_message = "pipeline_name must not be empty."
  }
}
variable "enabled" {
  type        = bool
  default     = true
  description = "Whether the rule is active. True, because without it nothing starts the pipeline on a push and the demo has to be started by hand every time. Set false to watch that difference: pushes then land in the registry and the cluster stays as it was"
}
