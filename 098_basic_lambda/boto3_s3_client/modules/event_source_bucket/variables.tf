variable "bucket_name" {
  type        = string
  description = "Exact name of the bucket. Composed by the caller rather than here, so the one place that knows the sensitive-<random> shape is the root (rules.md B-3/B-5)"

  validation {
    # S3's own rules, checked here because the alternative is an apply-time InvalidBucketName from the
    # CreateBucket call, which arrives after everything else in the plan has already been created.
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name)) && !can(regex("\\.\\.|^xn--|-s3alias$", var.bucket_name))
    error_message = "bucket_name must be 3-63 characters of lowercase letters, digits, dots and hyphens, start and end alphanumerically, contain no consecutive dots, and not use the xn-- prefix or -s3alias suffix that S3 reserves."
  }
}
variable "versioning_status" {
  type        = string
  default     = "Enabled"
  description = "Versioning state applied to the bucket"

  validation {
    condition     = contains(["Enabled", "Suspended"], var.versioning_status)
    error_message = "versioning_status must be Enabled or Suspended - the only two values S3's PutBucketVersioning accepts."
  }
}
variable "force_destroy" {
  type        = bool
  default     = true
  description = "Whether terraform destroy deletes the bucket's contents - including every object version and delete marker, since versioning is on - before deleting the bucket itself. False leaves a destroy to fail with BucketNotEmpty once anything has been uploaded"
}
variable "block_public_access" {
  type        = bool
  default     = true
  description = "Whether all four public-access blocks are switched on. True, which the _monolithic template left unstated and therefore inherited from the account's default. Stating it matters for a bucket whose purpose is holding unmasked personal data: the account default is on today, but a bucket that relies on an account setting is one API call away from being readable"
}
variable "notification_filter_prefix" {
  type        = string
  default     = null
  description = "Key prefix uploads have to carry to invoke the function. This module does not configure the notification - the root does, for the reasons in main.tf - and takes the value only so the verification command it exposes uploads to a key that actually triggers something. Null builds a command that uploads to the bucket root, which is correct when the root configures no filter"

  validation {
    condition     = var.notification_filter_prefix == null || can(regex("^[^/].*/$", var.notification_filter_prefix))
    error_message = "notification_filter_prefix must not begin with a slash and must end with one (e.g. incoming/), or be null."
  }
}
variable "masked_object_prefix" {
  type        = string
  default     = "masked/"
  description = "Prefix the handler writes its output under, used only to build the command that lists results. The value is owned by index.py, not by this module"

  validation {
    condition     = can(regex("^[^/].*/$", var.masked_object_prefix))
    error_message = "masked_object_prefix must not begin with a slash and must end with one (e.g. masked/)."
  }
}
