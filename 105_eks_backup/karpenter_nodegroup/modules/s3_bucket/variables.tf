variable "bucket_prefix" {
  type        = string
  default     = "eks-mountpoint-s3-"
  description = "Prefix AWS appends a unique suffix to when naming the bucket. A prefix rather than a fixed name because S3 bucket names are globally unique, so a literal name makes the project fail to apply for the second person who tries it. The _monolithic template sidestepped this by letting CloudFormation generate the whole name, which left nothing readable to look for in the console"
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,36}$", var.bucket_prefix))
    error_message = "bucket_prefix must be 2-37 characters of lowercase letters, digits, dots or hyphens and start with a letter or digit, leaving room for the suffix AWS appends within the 63-character bucket name limit."
  }
}
variable "force_destroy" {
  type        = bool
  default     = true
  description = "Whether terraform destroy may delete a bucket that still holds objects. True here because the demo pod writes files into it, and S3 refuses to delete a non-empty bucket - leaving destroy stuck on a bucket nobody wants to keep"
}
variable "versioning_enabled" {
  type        = bool
  default     = false
  description = "Whether object versioning is enabled. Off by default: Mountpoint overwrites files in place and versioning would retain every intermediate write, which also keeps the bucket non-empty after force_destroy deletes the current versions"
}
variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to the bucket, merged on top of its Name tag"
  validation {
    condition     = alltrue([for key in keys(var.tags) : length(key) > 0])
    error_message = "tags must not contain empty tag keys."
  }
}

variable "lifecycle_rules" {
  type = map(object({
    prefix                   = optional(string, "")
    enabled                  = optional(bool, true)
    transition_days          = optional(number)
    transition_storage_class = optional(string, "GLACIER")
    expiration_days          = optional(number)
  }))
  default = {
    # The rule the _monolithic template declared: objects written under glacier/ move to Glacier after
    # two weeks and are deleted after a year. Keyed by rule id.
    GlacierRule = {
      prefix          = "glacier"
      transition_days = 14
      expiration_days = 365
    }
  }
  description = "Lifecycle rules, keyed by rule id. Empty omits the lifecycle configuration entirely, which is what the API wants - an empty rule set is rejected (rules.md B-4)"

  validation {
    condition = alltrue([
      for r in values(var.lifecycle_rules) :
      r.transition_days != null || r.expiration_days != null
    ])
    error_message = "each lifecycle rule must set transition_days or expiration_days; a rule that does neither is rejected by S3."
  }

  validation {
    condition = alltrue([
      for r in values(var.lifecycle_rules) :
      r.transition_days == null || contains(["GLACIER", "GLACIER_IR", "DEEP_ARCHIVE", "STANDARD_IA", "ONEZONE_IA", "INTELLIGENT_TIERING"], r.transition_storage_class)
    ])
    error_message = "lifecycle rule transition_storage_class must be one of the storage classes S3 accepts for a transition: GLACIER, GLACIER_IR, DEEP_ARCHIVE, STANDARD_IA, ONEZONE_IA or INTELLIGENT_TIERING."
  }

  validation {
    condition = alltrue([
      for r in values(var.lifecycle_rules) :
      r.transition_days == null || r.expiration_days == null || r.expiration_days > r.transition_days
    ])
    error_message = "a lifecycle rule's expiration_days must be greater than its transition_days; expiring before the transition makes the transition unreachable."
  }
}
