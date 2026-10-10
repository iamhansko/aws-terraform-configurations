variable "bucket_prefix" {
  type        = string
  description = "Prefix for the generated bucket name. The _monolithic template declared the bucket with no name at all, so CloudFormation generated one; the prefix keeps that property and says what the bucket is for"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]*$", var.bucket_prefix)) && length(var.bucket_prefix) <= 37
    error_message = "bucket_prefix must be 1-37 characters of lowercase letters, digits, dots and hyphens, starting with a letter or digit (S3 caps bucket_prefix at 37 so the generated name stays within 63)."
  }
}
variable "force_destroy" {
  type        = bool
  default     = true
  description = "Whether terraform destroy empties the bucket first. True because every object in it is written by the workbench rather than by Terraform - the Lambda package, the GameLift server build and the client archive - so without it destroy stops at BucketNotEmpty. Those uploads are deleted with the bucket"
}
