variable "key_name" {
  type        = string
  description = "Name of the EC2 key pair to create. The _monolithic template built this by slicing a segment out of a uuid that stood in for AWS::StackId; the caller passes a plain name, and its variable records why a fixed one is safe here"

  validation {
    condition     = can(regex("^[ -~]{1,255}$", var.key_name))
    error_message = "key_name must be a non-empty string of printable ASCII characters, 255 characters or fewer."
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
