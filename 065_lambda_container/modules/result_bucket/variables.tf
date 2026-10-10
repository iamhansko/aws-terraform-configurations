variable "bucket_prefix" {
  type        = string
  description = "Prefix for the generated bucket name. A prefix rather than a fixed name, because bucket names are globally unique"
  validation {
    # 37 is S3's own cap on bucket_prefix: it leaves room for the suffix the provider generates.
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,36}$", var.bucket_prefix))
    error_message = "bucket_prefix must be 2-37 characters of lowercase letters, digits, dots and hyphens. 37 is S3's limit on a bucket_prefix."
  }
}
variable "force_destroy" {
  type        = bool
  default     = true
  description = "Whether terraform destroy empties the bucket before deleting it. True, because the function writes an object here that Terraform did not create, and the destroy would otherwise stop at BucketNotEmpty. The page goes with it"
}
