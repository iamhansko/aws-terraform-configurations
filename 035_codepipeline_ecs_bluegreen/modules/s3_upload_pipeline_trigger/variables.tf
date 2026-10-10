variable "name" {
  type        = string
  description = "Name of the EventBridge rule"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]{1,64}$", var.name))
    error_message = "name must be 1-64 characters of letters, digits, dots, underscores and hyphens."
  }
}
variable "description" {
  type        = string
  description = "Description of the rule. Worth filling in: CodePipeline's console writes an equivalent rule of its own with a warning not to delete it, and this one replaces that"

  validation {
    condition     = length(var.description) > 0 && length(var.description) <= 512
    error_message = "description must be 1-512 characters, which is the EventBridge limit."
  }
}
variable "event_bus_name" {
  type        = string
  default     = "default"
  description = "Bus the rule lives on, as the _monolithic template had it. CloudTrail delivers API call events to the default bus only, so a custom bus here would leave the rule silent"

  validation {
    condition     = var.event_bus_name == "default"
    error_message = "event_bus_name must be default. CloudTrail-delivered AWS API Call events only ever arrive on the account's default bus, so a rule on a custom bus would never match anything."
  }
}
variable "enabled" {
  type        = bool
  default     = true
  description = "Whether the rule is enabled. Disabling it leaves the pipeline working when started by hand and silent on an upload, because the source action does not poll"
}
variable "event_names" {
  type        = list(string)
  default     = ["CopyObject", "PutObject", "CompleteMultipartUpload"]
  description = "S3 API operations that count as a new archive, as the _monolithic template had them. All three matter: a small upload is PutObject, a larger one is CompleteMultipartUpload, and a copy within S3 is CopyObject"

  validation {
    condition     = length(var.event_names) > 0
    error_message = "event_names must not be empty. An empty list matches nothing, so the rule would never fire."
  }
  validation {
    condition     = alltrue([for name in var.event_names : contains(["PutObject", "CopyObject", "CompleteMultipartUpload"], name)])
    error_message = "event_names must contain only PutObject, CopyObject or CompleteMultipartUpload. Those are the three write operations that can create an object, and the trail records write-only data events."
  }
}
variable "bucket_name" {
  type        = string
  description = "Bucket the pattern matches. Taken from the bucket module so the pattern, the trail selector, the pipeline source and the bastion's upload all name one bucket (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "bucket_name must be a valid S3 bucket name."
  }
}
variable "object_key" {
  type        = string
  default     = "src.zip"
  description = "Key the pattern matches. This has to be the key the pipeline's source action reads and the key the trail's selector records, or the rule fires for writes the pipeline ignores - or never fires at all (rules.md B-5)"

  validation {
    condition     = can(regex("^[A-Za-z0-9!._*'()/-]+$", var.object_key))
    error_message = "object_key must be a valid S3 key with no spaces. It is matched exactly rather than as a prefix, so it has to be the whole key."
  }
}
variable "pipeline_arn" {
  type        = string
  description = "ARN of that pipeline, which is both the target and the only resource the role's policy allows StartPipelineExecution on"

  validation {
    condition     = can(regex("^arn:aws[a-zA-Z-]*:codepipeline:", var.pipeline_arn))
    error_message = "pipeline_arn must be a CodePipeline ARN."
  }
}
variable "target_id" {
  type        = string
  default     = "codepipeline"
  description = "Identifier of the target within the rule. Cosmetic, and only ever seen in the rule's own description of itself"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]{1,64}$", var.target_id))
    error_message = "target_id must be 1-64 characters of letters, digits, dots, underscores and hyphens."
  }
}
variable "role_name_prefix" {
  type        = string
  description = "Prefix the EventBridge role name is generated from, replacing the _monolithic template's CloudWatchEventRuleRole plus a uuid-derived suffix"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,38}$", var.role_name_prefix))
    error_message = "role_name_prefix must be 1-38 characters from the IAM role name character set, leaving room for the generated suffix inside IAM's 64 character limit."
  }
}
