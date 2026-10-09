variable "key_name_prefix" {
  type        = string
  description = "Prefix for the generated EC2 key pair name. A prefix rather than a fixed name because a key pair name is account-wide: a fixed one fails a second deployment with InvalidKeyPair.Duplicate"

  validation {
    condition     = can(regex("^[ -~]{1,200}$", var.key_name_prefix))
    error_message = "key_name_prefix must be 1-200 printable ASCII characters, leaving room for the generated suffix inside the 255 character key pair name limit."
  }
}
variable "rsa_bits" {
  type        = number
  description = "Size of the generated RSA key. The _monolithic template used 4096"

  validation {
    condition     = contains([2048, 3072, 4096], var.rsa_bits)
    error_message = "rsa_bits must be 2048, 3072 or 4096."
  }
}
