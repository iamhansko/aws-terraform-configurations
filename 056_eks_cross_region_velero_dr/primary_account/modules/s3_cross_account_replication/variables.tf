variable "role_name" {
  type        = string
  description = "Name of the replication role, and one of the two names the two accounts have to agree on. Required rather than generated: the destination account's bucket policy names this role as a literal principal ARN, and a generated name would leave that policy pointing at a role that does not exist - with the only symptom being objects whose replication status stays FAILED (rules.md I-2). The cost of the fixed name is that this project cannot be deployed twice into one account"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,64}$", var.role_name))
    error_message = "role_name must be 1-64 characters of the set IAM accepts for a role name."
  }
}
variable "source_account_id" {
  type        = string
  description = "Account this configuration is applied into. Used in the role's trust condition so only this account's S3 can assume it"

  validation {
    condition     = can(regex("^[0-9]{12}$", var.source_account_id))
    error_message = "source_account_id must be a 12-digit AWS account ID."
  }
}
variable "source_bucket_name" {
  type        = string
  description = "Name of the bucket being replicated from. Taken from the bucket module's output, so the replication configuration cannot be attached to a bucket that was never created (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.source_bucket_name))
    error_message = "source_bucket_name must be a valid S3 bucket name."
  }
}
variable "source_bucket_arn" {
  type        = string
  description = "ARN of the same bucket, used to scope the role's read permissions to it. Taken separately rather than derived from the name, because deriving it would put a second definition of the bucket's identity in this module"

  validation {
    condition     = can(regex("^arn:aws:s3:::", var.source_bucket_arn))
    error_message = "source_bucket_arn must be an S3 bucket ARN (arn:aws:s3:::<name>)."
  }
}
variable "destination_account_id" {
  type        = string
  description = "Account the destination bucket lives in. S3 refuses a cross-account replication configuration that does not state this explicitly"

  validation {
    condition     = can(regex("^[0-9]{12}$", var.destination_account_id))
    error_message = "destination_account_id must be a 12-digit AWS account ID."
  }
}
variable "destination_bucket_name" {
  type        = string
  description = "Name of the bucket in the other account. A literal string the caller agrees with that account's root rather than a reference, because the bucket is in a different state file and there is nothing to reference (rules.md I-2). A name that does not match is accepted here and fails at apply time with AccessDenied, which reads as a permissions problem rather than a typo"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.destination_bucket_name))
    error_message = "destination_bucket_name must be a valid S3 bucket name."
  }
}
variable "rule_id" {
  type        = string
  default     = "velero-backups-to-secondary"
  description = "ID of the replication rule. Named rather than left unset, which is how it reads in the console and in the replication status of a failed object"

  validation {
    condition     = length(var.rule_id) > 0 && length(var.rule_id) <= 255
    error_message = "rule_id must be 1-255 characters."
  }
}
variable "prefix" {
  type        = string
  default     = ""
  description = "Key prefix the rule applies to. Empty means every object, as the _monolithic template had it - and that is the right choice for a Velero bucket: narrowing it to backups/ would cover the backup archives and miss the metadata Velero writes beside them, leaving a destination bucket a restore cannot read"
}
variable "priority" {
  type        = number
  default     = 0
  description = "Rule priority, which only matters when rules overlap. There is one rule here, so this is 0 as the _monolithic template had it"

  validation {
    condition     = var.priority >= 0
    error_message = "priority must be zero or greater."
  }
}
variable "delete_marker_replication_status" {
  type        = string
  default     = "Enabled"
  description = "Whether a delete on the source is replicated. Enabled, and stated explicitly because the API defaults it to Disabled when omitted - which the _monolithic template did. Disabled on a backup bucket means a backup Velero has expired stays on the destination forever, where the destination's own lifecycle rules never see it"

  validation {
    condition     = contains(["Enabled", "Disabled"], var.delete_marker_replication_status)
    error_message = "delete_marker_replication_status must be either Enabled or Disabled."
  }
}
variable "replication_time_minutes" {
  type        = number
  default     = 15
  description = "Replication Time Control window, fifteen minutes as the _monolithic template had it. S3 commits to replicating 99.99% of objects within it and emits metrics when it does not - and charges extra per gigabyte replicated, which is worth knowing before leaving it on. Null turns both RTC and its metrics off and replicates on a best-effort basis"

  validation {
    condition     = var.replication_time_minutes == null || var.replication_time_minutes == 15
    error_message = "replication_time_minutes must be 15, which is the only value S3 accepts for Replication Time Control, or null to turn it off."
  }
}
