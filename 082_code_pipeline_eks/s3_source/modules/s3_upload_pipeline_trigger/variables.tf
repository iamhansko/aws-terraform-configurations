variable "name" {
  type        = string
  description = "Base name for the rule and its role"
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9._-]{1,50}$", var.name))
    error_message = "name must be 2-51 characters of letters, digits, dots, underscores and hyphens."
  }
}
variable "bucket_name" {
  type        = string
  description = "Bucket whose uploads start the pipeline. Taken from the module that created it rather than restated: the event pattern matches on this exact string, and a pattern naming a bucket that does not exist matches nothing and reports nothing (rules.md B-5)"
  validation {
    condition     = length(var.bucket_name) > 0
    error_message = "bucket_name must not be empty."
  }
}
variable "object_key" {
  type        = string
  description = "Key whose uploads start the pipeline. Has to be the object the pipeline's source stage reads - a rule triggering on one key while the source reads another starts an execution that redeploys the archive already there and succeeds (rules.md B-5)"
  validation {
    condition     = length(var.object_key) > 0
    error_message = "object_key must not be empty."
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
  description = "Whether the rule is active. True, because the pipeline's source stage has polling turned off, so without this rule nothing starts a run when a new archive is uploaded and the demo has to be started by hand every time. Set false to watch that difference: the upload lands in the bucket and the cluster stays as it was"
}
