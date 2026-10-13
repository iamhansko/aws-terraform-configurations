variable "bucket_prefix" {
  type        = string
  description = "Prefix for the generated bucket name. The SAM template let CloudFormation generate the whole name"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{0,36}$", var.bucket_prefix))
    error_message = "bucket_prefix must be 1-37 characters of lowercase letters, digits, periods and hyphens, starting with a letter or digit."
  }
}
variable "expiration_days" {
  type        = number
  default     = 30
  description = "Days a generated image stays in the bucket - and stays public - before S3 deletes it. Null keeps images forever, as the SAM template did. A chat message keeps its image URL, so an expired image shows as broken there"

  validation {
    condition     = var.expiration_days == null || try(var.expiration_days >= 1 && floor(var.expiration_days) == var.expiration_days, false)
    error_message = "expiration_days must be a positive whole number of days, or null."
  }
}
