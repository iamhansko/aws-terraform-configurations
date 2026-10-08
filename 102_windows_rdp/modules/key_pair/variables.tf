variable "key_name" {
  type        = string
  default     = null
  description = "Exact name for the key pair. Null generates one from key_name_prefix, which is the default and approximates what the _monolithic template did - a fixed name makes a second copy of this project in one account fail with InvalidKeyPair.Duplicate"

  validation {
    condition     = var.key_name == null || can(regex("^[ -~]{1,255}$", var.key_name))
    error_message = "key_name must be 1-255 printable ASCII characters, or null to generate one from key_name_prefix."
  }
}
variable "key_name_prefix" {
  type        = string
  default     = "windows-rdp-"
  description = "Prefix for the generated key pair name, used when key_name is null"

  validation {
    condition     = can(regex("^[ -~]{1,200}$", var.key_name_prefix))
    error_message = "key_name_prefix must be 1-200 printable ASCII characters, leaving room for the generated suffix inside the 255 character limit."
  }
}
variable "rsa_bits" {
  type        = number
  default     = 4096
  description = "Size of the generated RSA key, as the _monolithic template had it. EC2 accepts 1024, 2048 and 4096 for an imported RSA key"

  validation {
    condition     = contains([1024, 2048, 4096], var.rsa_bits)
    error_message = "rsa_bits must be 1024, 2048 or 4096, the sizes EC2 accepts for an imported RSA key pair."
  }
}
variable "parameter_name_prefix" {
  type        = string
  default     = "/ec2/keypair/"
  description = "Parameter Store path the private key is written under, with the key pair id appended. This is the path CloudFormation uses for a key pair it generates, which is why the _monolithic template wrote there"

  validation {
    condition     = startswith(var.parameter_name_prefix, "/") && endswith(var.parameter_name_prefix, "/")
    error_message = "parameter_name_prefix must start and end with a slash, because the key pair id is appended to it to form the full parameter name."
  }
}
