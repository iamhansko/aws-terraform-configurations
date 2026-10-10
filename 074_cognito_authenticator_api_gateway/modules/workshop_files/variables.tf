variable "bucket_prefix" {
  type        = string
  default     = "cognito-workshop-files-"
  description = "Prefix for the generated staging bucket name"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{0,36}$", var.bucket_prefix))
    error_message = "bucket_prefix must be 1-37 characters of lowercase letters, digits, periods and hyphens, starting with a letter or digit."
  }
}
variable "source_dir" {
  type        = string
  description = "Directory whose whole tree is staged. Read at plan"

  validation {
    condition     = length(var.source_dir) > 0
    error_message = "source_dir must not be empty."
  }
}
variable "key_prefix" {
  type        = string
  default     = "workshop"
  description = "Key prefix the tree is staged under, and the directory name it lands in on the instance"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.key_prefix))
    error_message = "key_prefix must be a single segment of lowercase letters, digits and hyphens."
  }
}
