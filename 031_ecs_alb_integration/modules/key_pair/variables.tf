variable "key_name_prefix" {
  type        = string
  default     = "key-"
  description = "Prefix for the generated key pair name. The provider appends a unique suffix, so two copies of this project in one account do not collide on the name"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]{1,200}$", var.key_name_prefix))
    error_message = "key_name_prefix must be 1-200 characters of letters, digits, dots, underscores or hyphens, leaving room for the suffix the provider appends within EC2's 255-character key name limit."
  }
}
variable "rsa_bits" {
  type        = number
  default     = 4096
  description = "Size of the generated RSA key"

  validation {
    condition     = contains([2048, 3072, 4096], var.rsa_bits)
    error_message = "rsa_bits must be 2048, 3072 or 4096."
  }
}
