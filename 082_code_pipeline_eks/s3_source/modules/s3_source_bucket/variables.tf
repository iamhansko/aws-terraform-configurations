variable "name" {
  type        = string
  description = "Base name for the bucket prefix. No default: the caller derives it from the project name"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,50}$", var.name))
    error_message = "name must be 2-51 characters of lowercase letters, digits, dots and hyphens - it becomes part of an S3 bucket name."
  }
}
variable "bucket_name" {
  type        = string
  default     = null
  description = "Fixed name for the bucket. Null generates one from name, which is what lets this project be deployed twice in one account: bucket names are globally unique, so a fixed name collides with a second copy of this project and with anyone else who got there first"

  validation {
    condition     = var.bucket_name == null || can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "bucket_name must be a valid S3 bucket name, or null to generate one."
  }
}
variable "object_key" {
  type        = string
  default     = "src.zip"
  description = "Key the application archive is uploaded to. This module owns the value and re-exposes it, so the pipeline's S3ObjectKey, the event pattern that starts the pipeline and the IAM statement that reads it all come from one place - a rule watching one key while the source reads another produces executions that redeploy the previous archive and report success (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9!._/-]+$", var.object_key))
    error_message = "object_key must be a plain S3 key of letters, digits and ! . _ - / characters."
  }
  validation {
    # CodePipeline's S3 source reads one object rather than a prefix, and the event pattern built from this
    # matches the key exactly, so a key ending in / would match nothing (rules.md B-1).
    condition     = !endswith(var.object_key, "/")
    error_message = "object_key must name an object, not a prefix: CodePipeline's S3 source reads a single object and the EventBridge pattern matches this key exactly."
  }
}
variable "enable_eventbridge_notifications" {
  type        = bool
  default     = true
  description = "Whether the bucket sends Object Created events to EventBridge. True, and it is what lets this variant work without a CloudTrail trail: the rule that starts the pipeline matches those events. Turning it off leaves the rule matching nothing, which looks exactly like a broken rule (rules.md B-4)"
}
variable "force_destroy" {
  type        = bool
  default     = true
  description = "Whether terraform destroy empties the bucket before deleting it. True, because the workbench uploads an archive here and versioning keeps every one of them, so a destroy would otherwise stop at BucketNotEmpty with the cluster already gone. Never true for a bucket holding anything worth keeping"
}
variable "noncurrent_version_expiration_days" {
  type        = number
  default     = 7
  description = "How long a superseded version of the archive is kept. Versioning cannot be turned off here - CodePipeline's S3 source requires it - so without this rule every upload is retained forever. Set null to keep them all"

  validation {
    condition     = var.noncurrent_version_expiration_days == null || var.noncurrent_version_expiration_days >= 1
    error_message = "noncurrent_version_expiration_days must be at least 1, or null to keep every version."
  }
}
