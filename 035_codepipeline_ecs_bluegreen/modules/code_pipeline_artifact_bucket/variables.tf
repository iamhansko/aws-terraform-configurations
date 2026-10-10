variable "bucket_prefix" {
  type        = string
  description = "Prefix the bucket name is generated from. A prefix rather than a fixed name because S3 bucket names are globally unique"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,36}$", var.bucket_prefix))
    error_message = "bucket_prefix must be 2-37 characters of lowercase letters, digits, dots and hyphens starting with a letter or digit, leaving room for the generated suffix inside the 63 character bucket name limit."
  }
}
variable "force_destroy" {
  type        = bool
  default     = true
  description = "Whether to delete the bucket together with the objects in it. True because every pipeline execution leaves two artefacts here and nothing removes them, so the bucket is never empty by the time a destroy reaches it. The cost is that the record of what was deployed when goes with it"
}
