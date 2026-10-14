variable "identity_store_id" {
  type        = string
  description = "Identity store of the IAM Identity Center instance the user is created in. Read by the caller from aws_ssoadmin_instances (rules.md B-6)"

  validation {
    condition     = can(regex("^d-[0-9a-f]{10}$|^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.identity_store_id))
    error_message = "identity_store_id must be an identity store ID such as d-1234567890."
  }
}
variable "user_name" {
  type        = string
  default     = "kiro"
  description = "Sign-in name, as the _monolithic template had it. Unique within the identity store, so a second copy of this root against the same Identity Center instance fails with ConflictException"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,128}$", var.user_name))
    error_message = "user_name must be 1-128 characters of letters, digits and +=,.@_-."
  }
}
variable "display_name" {
  type        = string
  default     = "Kiro User"
  description = "Display name, as the _monolithic template had it"

  validation {
    condition     = length(var.display_name) > 0 && length(var.display_name) <= 1024
    error_message = "display_name must be 1-1024 characters."
  }
}
variable "given_name" {
  type        = string
  default     = "Kiro"
  description = "Given name, as the _monolithic template had it"

  validation {
    condition     = length(var.given_name) > 0
    error_message = "given_name must not be empty."
  }
}
variable "family_name" {
  type        = string
  default     = "User"
  description = "Family name, as the _monolithic template had it"

  validation {
    condition     = length(var.family_name) > 0
    error_message = "family_name must not be empty."
  }
}
variable "email" {
  type        = string
  description = "Primary work email of the user"

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.email))
    error_message = "email must be an email address."
  }
}
