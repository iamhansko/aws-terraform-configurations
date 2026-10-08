variable "identity_store_id" {
  type        = string
  description = "Identity store of the IAM Identity Center instance the user is created in. Discovered by the caller rather than looked up here, because Identity Center is an account-level thing this module has no business resolving (rules.md B-6)"

  validation {
    condition     = can(regex("^d-[0-9a-z]+$", var.identity_store_id))
    error_message = "identity_store_id must look like an identity store id (e.g. d-1234567890)."
  }
}

variable "user_name" {
  type        = string
  default     = "argocd"
  description = "User name, which is what the person types to sign in"

  validation {
    condition     = can(regex("^[A-Za-z0-9._@+-]{1,128}$", var.user_name))
    error_message = "user_name must be 1-128 characters of letters, digits and . _ @ + -."
  }
}

variable "display_name" {
  type        = string
  default     = "Argo CD Demo User"
  description = "Display name shown in the Identity Center console and in the Argo CD UI"

  validation {
    condition     = length(var.display_name) > 0
    error_message = "display_name must not be empty."
  }
}

variable "given_name" {
  type        = string
  default     = "Argo"
  description = "Given name. Required by the identity store even for a demo account"

  validation {
    condition     = length(var.given_name) > 0
    error_message = "given_name must not be empty."
  }
}

variable "family_name" {
  type        = string
  default     = "User"
  description = "Family name. Required by the identity store even for a demo account"

  validation {
    condition     = length(var.family_name) > 0
    error_message = "family_name must not be empty."
  }
}

variable "email" {
  type        = string
  default     = "argocd@example.com"
  description = "Primary work email. Identity Center sends the one-time password to it, so a real address is needed to actually sign in - example.com is enough to create the user"

  validation {
    condition     = can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", var.email))
    error_message = "email must look like an email address."
  }
}
