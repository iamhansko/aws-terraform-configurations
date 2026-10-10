variable "key_name_prefix" {
  type        = string
  description = "Prefix the generated key pair name is built from. A prefix rather than a fixed name because key pair names are account-wide and a fixed one collides with a second copy of this project"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]{1,200}$", var.key_name_prefix))
    error_message = "key_name_prefix must be 1-200 characters of letters, digits, dots, underscores or hyphens. The provider appends a generated suffix, so the whole name has to stay inside the 255 character key pair name limit."
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
variable "parameter_description" {
  type        = string
  default     = "Private key of the generated EC2 key pair, written here the way CloudFormation files an AWS::EC2::KeyPair"
  description = "Description attached to the SecureString parameter holding the private key"

  validation {
    condition     = length(var.parameter_description) > 0
    error_message = "parameter_description must not be empty."
  }
}
