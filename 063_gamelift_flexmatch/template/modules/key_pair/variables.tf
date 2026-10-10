variable "key_name_prefix" {
  type        = string
  description = "Prefix for the generated key pair name. The provider appends a unique suffix, which is what keeps two copies of this project in one account from colliding"

  validation {
    condition     = can(regex("^[ -~]+$", var.key_name_prefix)) && length(var.key_name_prefix) <= 200
    error_message = "key_name_prefix must be 1-200 printable ASCII characters, leaving room for the suffix the provider appends."
  }
}
variable "rsa_bits" {
  type        = number
  default     = 4096
  description = "Size of the generated RSA key, as the _monolithic template had it"

  validation {
    condition     = contains([2048, 3072, 4096], var.rsa_bits)
    error_message = "rsa_bits must be 2048, 3072 or 4096."
  }
}
