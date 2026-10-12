variable "bucket_prefix" {
  type        = string
  description = "Prefix for the generated bucket name. The SAM template let CloudFormation generate the whole name"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{0,36}$", var.bucket_prefix))
    error_message = "bucket_prefix must be 1-37 characters of lowercase letters, digits, periods and hyphens, starting with a letter or digit."
  }
}
