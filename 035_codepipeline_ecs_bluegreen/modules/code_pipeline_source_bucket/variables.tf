variable "bucket_prefix" {
  type        = string
  description = "Prefix the bucket name is generated from. A prefix rather than a fixed name because S3 bucket names are globally unique"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,36}$", var.bucket_prefix))
    error_message = "bucket_prefix must be 2-37 characters of lowercase letters, digits, dots and hyphens starting with a letter or digit, leaving room for the generated suffix inside the 63 character bucket name limit."
  }
}
variable "object_key" {
  type        = string
  default     = "src.zip"
  description = "Key the pipeline's source action reads, re-exposed as an output together with its ARN so that the bastion's upload, the pipeline's source configuration, the CloudTrail data selector and the EventBridge pattern are all built from one value (rules.md B-5)"

  validation {
    condition     = can(regex("^[A-Za-z0-9!._*'()-]+\\.zip$", var.object_key))
    error_message = "object_key must be a single .zip filename with no slashes. The CodePipeline S3 source action requires a zip archive, and the bastion uses the same string as a local filename."
  }
}
variable "force_destroy" {
  type        = bool
  default     = true
  description = "Whether to delete the bucket together with every object and object version in it. True because this bucket is never empty by the time a destroy reaches it, and because versioning is required here, which means this discards the archive's whole history and is not reversible"
}
