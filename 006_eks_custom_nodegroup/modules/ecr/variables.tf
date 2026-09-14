variable "name" {
  type        = string
  default     = "stem-ecr"
  description = "Name of the ECR repository"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9._/-]{1,255}$", var.name))
    error_message = "name must be a valid ECR repository name (lowercase letters, digits, and . _ / -)."
  }
}
variable "force_delete" {
  type        = bool
  default     = true
  description = "Whether terraform destroy may delete the repository while it still holds images. True keeps the demo tear-down from wedging on the image the bastion pushed; set false for anything holding artifacts worth keeping"
}
variable "image_tag_mutability" {
  type        = string
  default     = "MUTABLE"
  description = "Whether an existing tag can be overwritten. MUTABLE is required here because the bastion pushes to the ':latest' tag on every boot"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be either MUTABLE or IMMUTABLE."
  }
}
variable "scan_on_push" {
  type        = bool
  default     = true
  description = "Whether ECR runs a basic vulnerability scan when an image is pushed"
}
variable "encryption_type" {
  type        = string
  default     = "AES256"
  description = "Server-side encryption used for images at rest. KMS additionally requires kms_key_arn"

  validation {
    condition     = contains(["AES256", "KMS"], var.encryption_type)
    error_message = "encryption_type must be either AES256 or KMS."
  }
}
variable "kms_key_arn" {
  type        = string
  default     = null
  description = "Customer managed KMS key ARN used when encryption_type is KMS. When null, ECR uses an AWS managed key"

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws:kms:", var.kms_key_arn))
    error_message = "kms_key_arn must be a valid KMS key ARN, or null."
  }
}
