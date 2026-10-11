variable "name" {
  type        = string
  default     = null
  description = "Optional fixed bucket name. Null generates one from name_prefix, which is what lets this project be deployed twice - an S3 bucket name is globally unique across every AWS account, so a fixed name collides with anyone who got there first and the error says the name is taken rather than that it is in use elsewhere"

  validation {
    condition     = var.name == null || can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.name))
    error_message = "name must be 3-63 characters of lowercase letters, digits, dots and hyphens, starting and ending with a letter or digit, or null."
  }
}
variable "name_prefix" {
  type        = string
  default     = "teleport-sessions-"
  description = "Prefix for the generated bucket name when name is null"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{0,36}$", var.name_prefix))
    error_message = "name_prefix must be lowercase letters, digits, dots and hyphens, starting with a letter or digit, and short enough to leave room for the generated suffix."
  }
}
variable "versioning_enabled" {
  type        = bool
  default     = true
  description = "Whether object versioning is on. True, and not optional in practice: Teleport requires versioning on a session recording bucket and checks for it at startup, because a recording is written as a series of uploads and it relies on versions to reconcile them. The _monolithic template created the bucket with no versioning configuration at all and instead granted the writer s3:PutBucketVersioning, leaving the cluster to turn on a property of infrastructure Terraform owns"

  validation {
    # Pinned in the direction the consumer requires (rules.md B-1). Turning it off does
    # not fail an apply - it fails Teleport's own audit backend initialisation, minutes
    # later, in a pod log.
    condition     = var.versioning_enabled
    error_message = "versioning_enabled must be true: Teleport requires versioning on its session recording bucket and rejects one without it at startup. Nothing in the Terraform apply reports this - it surfaces as an auth pod that will not become ready."
  }
}
variable "sse_algorithm" {
  type        = string
  default     = "AES256"
  description = "Server-side encryption applied to every object. AES256 uses keys S3 manages and needs no key policy; aws:kms lets a customer managed key be used, at the cost of granting the recording writer and every reader kms:Decrypt on it. Session recordings are a transcript of everything an operator typed on a production system, so this is not a formality"

  validation {
    condition     = contains(["AES256", "aws:kms"], var.sse_algorithm)
    error_message = "sse_algorithm must be either AES256 or aws:kms."
  }
}
variable "kms_key_arn" {
  type        = string
  default     = null
  description = "Customer managed key used when sse_algorithm is aws:kms. Null lets S3 use the account's default aws/s3 key"

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws:kms:", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN, or null."
  }
  validation {
    # Cross-variable, available since Terraform 1.9 (rules.md B-1). A key named alongside
    # AES256 is accepted by Terraform and ignored by S3, which reads as encryption with a
    # key that is not actually being used.
    condition     = var.kms_key_arn == null || var.sse_algorithm == "aws:kms"
    error_message = "kms_key_arn only applies when sse_algorithm is aws:kms; S3 ignores it otherwise, leaving objects encrypted with a different key than the one named here."
  }
}
variable "force_destroy" {
  type        = bool
  default     = true
  description = "Whether terraform destroy may delete the bucket while recordings remain in it. True for a demo, because the recordings are written by Teleport rather than by Terraform, so there is nothing in state to remove first and destroy would otherwise fail on a non-empty bucket. Worth reversing anywhere the recordings are the audit trail - which is what they are for"
}
variable "noncurrent_version_expiration_days" {
  type        = number
  default     = 30
  description = "How long superseded object versions are kept. Versioning is required, so every overwrite leaves a version behind and without an expiry rule the bucket grows without limit - including versions of recordings that were deleted, which keep their storage cost and their contents. Set to 0 to keep them indefinitely"

  validation {
    condition     = var.noncurrent_version_expiration_days >= 0
    error_message = "noncurrent_version_expiration_days must be zero or greater; zero disables the rule."
  }
}
