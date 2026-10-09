variable "key_name" {
  type        = string
  description = "Name of the EC2 key pair. Account- and region-unique, so a second apply of this root into the same account fails with InvalidKeyPair.Duplicate - the trade for dropping the _monolithic template's uuid-derived name (see the root's providers.tf)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]{1,255}$", var.key_name))
    error_message = "key_name must be 1-255 characters of letters, digits, dots, underscores or hyphens."
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
