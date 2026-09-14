variable "bucket_name" {
  type        = string
  default     = null
  description = "Explicit bucket name. When null, a unique name is generated from bucket_name_prefix, which avoids colliding with the globally shared S3 namespace"

  validation {
    condition     = var.bucket_name == null || can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "bucket_name must be a valid S3 bucket name (3-63 lowercase characters, digits, dots and hyphens), or null."
  }
}

variable "bucket_name_prefix" {
  type        = string
  default     = "s3-sync-local-"
  description = "Prefix for the generated bucket name, used when bucket_name is null"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{0,36}$", var.bucket_name_prefix))
    error_message = "bucket_name_prefix must be 37 characters or fewer of lowercase letters, digits, dots and hyphens, starting with a letter or digit."
  }
}

variable "force_destroy" {
  type        = bool
  default     = true
  description = "Whether terraform destroy may delete the bucket while it still holds objects"
}

variable "sse_algorithm" {
  type        = string
  default     = "AES256"
  description = "Server-side encryption applied by default"

  validation {
    condition     = contains(["AES256", "aws:kms"], var.sse_algorithm)
    error_message = "sse_algorithm must be either AES256 or aws:kms."
  }
}

variable "versioning_enabled" {
  type        = bool
  default     = false
  description = "Whether object versioning is enabled. Left off because it interacts badly with force_destroy on a demo bucket: every overwrite the sync performs keeps a noncurrent version around"
}
