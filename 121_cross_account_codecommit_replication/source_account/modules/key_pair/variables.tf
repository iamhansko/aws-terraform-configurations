variable "key_name" {
  type        = string
  default     = null
  description = "Optional exact key-pair name; null generates one from key_name_prefix."

  validation {
    condition     = var.key_name == null || can(regex("^[ -~]{1,255}$", var.key_name))
    error_message = "key_name must be 1-255 printable ASCII characters, or null."
  }
}

variable "key_name_prefix" {
  type        = string
  description = "Prefix used when generating the key-pair name."

  validation {
    condition     = can(regex("^[ -~]{1,200}$", var.key_name_prefix))
    error_message = "key_name_prefix must be 1-200 printable ASCII characters."
  }
}

variable "rsa_bits" {
  type        = number
  description = "Size of the generated RSA private key."

  validation {
    condition     = contains([2048, 3072, 4096], var.rsa_bits)
    error_message = "rsa_bits must be 2048, 3072, or 4096."
  }
}
