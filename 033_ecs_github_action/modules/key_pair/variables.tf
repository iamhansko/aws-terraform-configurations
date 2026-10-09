variable "key_name" {
  type        = string
  default     = null
  description = "Explicit key pair name. When null, the provider generates one from key_name_prefix, which is what keeps two copies of this project in one account from colliding"

  validation {
    condition     = var.key_name == null || can(regex("^[ -~]{1,255}$", var.key_name))
    error_message = "key_name must be a string of printable ASCII characters (255 or fewer), or null to generate one from key_name_prefix."
  }
}
variable "key_name_prefix" {
  type        = string
  default     = "ecs-cicd-"
  description = "Prefix for the generated key pair name, used only when key_name is null"

  validation {
    condition     = can(regex("^[ -~]{1,200}$", var.key_name_prefix))
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
