variable "name_prefix" {
  type        = string
  description = "Prefix for the generated bucket name. A prefix rather than a fixed name: bucket names are globally unique"

  validation {
    # 37 is S3's own cap on bucket_prefix, not a margin chosen here - it leaves room for the suffix the
    # service generates. Without this bound the failure is "expected length of bucket_prefix to be in the
    # range (0 - 37)" from the provider, which names neither this variable nor the one that fed it
    # (rules.md B-1).
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,36}$", var.name_prefix))
    error_message = "name_prefix must be 2-37 characters of lowercase letters, digits, dots and hyphens. 37 is S3's limit on a bucket_prefix, which leaves room for the suffix it generates."
  }
}
variable "replication_role_arn" {
  type        = string
  description = "Role S3 assumes to replicate. Passed in from the module that creates it, so the configuration and the role cannot name different things (rules.md B-5)"

  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:role/", var.replication_role_arn))
    error_message = "replication_role_arn must be an IAM role ARN."
  }
}
variable "destination_bucket_arn" {
  type        = string
  description = "Bucket in the other account that objects are replicated into"

  validation {
    condition     = can(regex("^arn:aws:s3:::", var.destination_bucket_arn))
    error_message = "destination_bucket_arn must be an S3 bucket ARN."
  }
}
variable "destination_account_id" {
  type        = string
  description = "Account that owns the destination bucket. S3 requires this on a cross-account rule: it is the check that stops a replication rule from being pointed at someone else's bucket by name alone"

  validation {
    condition     = can(regex("^[0-9]{12}$", var.destination_account_id))
    error_message = "destination_account_id must be a 12-digit AWS account ID."
  }
}
variable "replicate_owner_override" {
  type        = bool
  default     = true
  description = "Whether to hand ownership of replicated objects to the destination account. True, and it has to match the destination bucket's policy. Without it a cross-account replica stays owned by this account and the destination account cannot read an object in its own bucket"
}
variable "rule_prefix" {
  type        = string
  default     = ""
  description = "Key prefix the rule applies to. Empty means everything, as the _monolithic template had it"
  validation {
    condition     = !startswith(var.rule_prefix, "/") && length(var.rule_prefix) <= 1024
    error_message = "rule_prefix must not start with a slash - S3 keys never do, so such a rule replicates nothing - and must be at most 1024 characters."
  }
}
variable "replication_time_minutes" {
  type        = number
  default     = null
  description = <<-DESC
    Replication Time Control target, in minutes. The _monolithic template set 15, which is the only value
    S3 accepts - but RTC is a paid feature with its own per-gigabyte charge, and enabling it also switches
    on replication metrics whether or not they are asked for.

    Null turns it off, which is the default here. Set 15 to get the original's behaviour and the compliance
    guarantee it buys.
  DESC

  validation {
    condition     = var.replication_time_minutes == null || var.replication_time_minutes == 15
    error_message = "replication_time_minutes must be 15, which is the only value S3 accepts, or null to leave Replication Time Control off."
  }
}
variable "replicate_delete_markers" {
  type        = bool
  default     = true
  description = "Whether deleting an object in the source also places a delete marker in the destination, as the _monolithic template had it. Note what it does not do: S3 never replicates a delete of a specific version, so this cannot be used to erase a replica"
}
variable "noncurrent_version_expiration_days" {
  type        = number
  default     = 30
  description = "How long a superseded version is kept in the source. Versioning cannot be turned off on a replication source, so without a rule every version is retained forever. Set null to keep them all"

  validation {
    condition     = var.noncurrent_version_expiration_days == null || var.noncurrent_version_expiration_days >= 1
    error_message = "noncurrent_version_expiration_days must be at least 1, or null to keep every version."
  }
}
variable "objects" {
  type        = map(string)
  default     = {}
  description = "Objects written into the source bucket, keyed by key with the body as the value. The _monolithic template created two empty buckets and a replication rule, so there was nothing to replicate and no way to tell whether any of it worked"

  validation {
    condition     = alltrue([for key in keys(var.objects) : can(regex("^[^/]", key))])
    error_message = "objects keys must not start with a slash."
  }
}
variable "force_destroy" {
  type        = bool
  default     = true
  description = "Whether terraform destroy empties the bucket before deleting it. True, because this module writes demo objects and versioning keeps every one of them. Never true for a bucket holding anything worth keeping"
}
