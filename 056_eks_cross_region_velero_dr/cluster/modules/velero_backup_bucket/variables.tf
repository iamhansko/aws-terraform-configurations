variable "bucket_name" {
  type        = string
  default     = null
  description = "Fixed bucket name. Null generates one from bucket_name_prefix, which is right when nothing outside this configuration has to name the bucket - the cluster variant's case. The cross-account variants must set it, because the other account's replication configuration names this bucket as a literal string and cannot reference it (rules.md I-2)"

  validation {
    condition     = var.bucket_name == null || can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "bucket_name must be 3-63 characters of lowercase letters, digits, dots and hyphens, starting and ending alphanumerically, or null."
  }
}
variable "bucket_name_prefix" {
  type        = string
  default     = "velero-backup-"
  description = "Prefix for the generated bucket name when bucket_name is null"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{0,36}$", var.bucket_name_prefix))
    error_message = "bucket_name_prefix must be lowercase letters, digits, dots and hyphens, starting alphanumerically, and short enough to leave room for the generated suffix."
  }
}
variable "force_destroy" {
  type        = bool
  default     = true
  description = "Whether terraform destroy deletes the bucket's contents along with it. True for a demo, and stated explicitly rather than left at its default because of what it means here: Velero's backups are objects no apply created, so with this false the destroy fails with BucketNotEmpty - and with it true every backup and every version of every backup is deleted, which is not recoverable (rules.md I-4)"
}
variable "block_public_policy" {
  type        = bool
  default     = true
  description = "Whether S3 rejects bucket policies that would grant public access. True, and safe to leave true even on the receiving side of a cross-account replication: a policy naming another account's role is not a public policy, so BlockPublicPolicy does not reject it"
}
variable "abort_incomplete_multipart_upload_days" {
  type        = number
  default     = 7
  description = "How long an interrupted multipart upload is kept before S3 discards its parts. Velero uploads backups in parts, so a failed or cancelled backup leaves parts that are billed and appear in no object listing - the _monolithic template had no lifecycle configuration at all, which is the quietest way to spend money on this kind of bucket"

  validation {
    condition     = var.abort_incomplete_multipart_upload_days >= 1
    error_message = "abort_incomplete_multipart_upload_days must be at least 1."
  }
}
variable "noncurrent_version_expiration_days" {
  type        = number
  default     = 30
  description = "How long a superseded backup version is kept. Versioning is mandatory here (S3 replication requires it), so without this rule every overwritten backup accumulates forever. Null keeps them indefinitely, which is the _monolithic template's behaviour"

  validation {
    condition     = var.noncurrent_version_expiration_days == null || var.noncurrent_version_expiration_days >= 1
    error_message = "noncurrent_version_expiration_days must be at least 1, or null to keep noncurrent versions indefinitely."
  }
}
variable "replication_source_role_arns" {
  type        = list(string)
  default     = []
  description = "ARNs of replication roles in other accounts allowed to write into this bucket. Empty on a bucket that is not a replication destination, which leaves the bucket policy out entirely (rules.md B-4). Each ARN is a literal string the caller assembles from an account ID and an agreed role name, because that role is in a different account and a different state file (rules.md I-2)"

  validation {
    condition     = alltrue([for arn in var.replication_source_role_arns : can(regex("^arn:aws:iam::[0-9]{12}:role/", arn))])
    error_message = "replication_source_role_arns must contain IAM role ARNs (arn:aws:iam::<account>:role/<name>)."
  }
}
