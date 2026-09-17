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
