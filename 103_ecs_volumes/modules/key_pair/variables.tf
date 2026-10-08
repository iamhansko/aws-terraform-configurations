variable "key_name" {
  type        = string
  default     = null
  description = "Exact name for the key pair. Null generates one from key_name_prefix, which is the default and the behaviour the _monolithic template approximated with a uuid slice - a fixed name makes a second copy of this project in the same account fail with InvalidKeyPair.Duplicate"

  validation {
    condition     = var.key_name == null || can(regex("^[ -~]{1,255}$", var.key_name))
    error_message = "key_name must be 1-255 printable ASCII characters, or null to generate one from key_name_prefix."
  }
}
variable "key_name_prefix" {
  type        = string
  default     = "ecs-volumes-"
  description = "Prefix for the generated key pair name, used when key_name is null"

  validation {
    condition     = can(regex("^[ -~]{1,200}$", var.key_name_prefix))
    error_message = "key_name_prefix must be 1-200 printable ASCII characters, leaving room for the generated suffix inside the 255 character limit."
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
