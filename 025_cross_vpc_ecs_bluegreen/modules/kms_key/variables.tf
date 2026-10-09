variable "description" {
  type        = string
  description = "Description shown on the key. The _monolithic template left it unset, so the console listed an unnamed key next to the alias and nothing said what it encrypted"

  validation {
    condition     = length(var.description) > 0 && length(var.description) <= 8192
    error_message = "description must be between 1 and 8192 characters."
  }
}
variable "alias_name" {
  type        = string
  description = "Alias for the key, including the alias/ prefix. An alias name is region-wide, so a second copy of this project in one region fails here with AlreadyExistsException"

  validation {
    condition     = can(regex("^alias/[a-zA-Z0-9/_-]{1,250}$", var.alias_name))
    error_message = "alias_name must start with alias/ followed by 1-250 characters of letters, digits and the set /_- that KMS accepts."
  }
}
variable "enable_key_rotation" {
  type        = bool
  description = "Whether KMS rotates the key material automatically. The _monolithic template enabled it"
}
variable "rotation_period_in_days" {
  type        = number
  description = "Days between automatic rotations. Only meaningful when enable_key_rotation is true"

  validation {
    condition     = var.rotation_period_in_days >= 90 && var.rotation_period_in_days <= 2560
    error_message = "rotation_period_in_days must be between 90 and 2560, the range KMS accepts."
  }
}
variable "deletion_window_in_days" {
  type        = number
  description = "Days KMS waits before destroying the key after terraform destroy. The _monolithic template left this unset, taking the provider default of 30 - which means a destroyed and recreated project leaves the old key pending deletion for a month, and its alias is held against the new one until the alias is moved. A short window suits a demo and makes the retry work"

  validation {
    condition     = var.deletion_window_in_days >= 7 && var.deletion_window_in_days <= 30
    error_message = "deletion_window_in_days must be between 7 and 30, the range KMS accepts."
  }
}
