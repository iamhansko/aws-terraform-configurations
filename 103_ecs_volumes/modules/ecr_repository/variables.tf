variable "name" {
  type        = string
  description = "Name of the repository. No default: it is derived from the project name by the caller, because CloudFormation generated this name and Terraform requires one"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9._/-]{1,255}$", var.name))
    error_message = "name must be 2-256 characters of lowercase letters, digits, dots, underscores, hyphens and slashes, starting with a letter or digit. An uppercase letter is rejected by ECR at apply time with InvalidParameterException, not by plan."
  }
}
variable "image_tag" {
  type        = string
  default     = "latest"
  description = "The tag the image builder pushes and the task definition pulls. One value, re-exposed as an output, so the two cannot name different tags - a mismatch is not an error anywhere, it is a service whose tasks stop with CannotPullContainerError while the image sits in the repository under another tag (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9._-]{0,127}$", var.image_tag))
    error_message = "image_tag must be 1-128 characters of letters, digits, dots, underscores and hyphens, starting with a letter or digit."
  }
}
variable "image_tag_mutability" {
  type        = string
  default     = "MUTABLE"
  description = "Whether a tag can be moved to a different image. MUTABLE, because the builder pushes over a single moving tag on every launch and IMMUTABLE would make the second apply of this project fail the push - which happens inside userdata, so it surfaces as an ECS service that never pulls rather than as a Terraform error"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be MUTABLE or IMMUTABLE."
  }
}
variable "force_delete" {
  type        = bool
  default     = true
  description = "Whether terraform destroy deletes the repository while it still holds images. True, as the _monolithic template had it: the builder puts an image here, so a destroy would otherwise stop at RepositoryNotEmptyException with the cluster already gone. Never true for a registry holding anything worth keeping"
}
variable "scan_on_push" {
  type        = bool
  default     = true
  description = "Whether ECR scans each pushed image for known vulnerabilities. On, where the _monolithic template left the repository at its defaults. A basic scan costs nothing and this image is a JDK base layer, which is the kind that accumulates findings between builds"
}
variable "encryption_type" {
  type        = string
  default     = "AES256"
  description = "How images are encrypted at rest. AES256 is ECR's own default, stated explicitly. KMS would add a key that the container instance role has to be allowed to use, and a missing grant there appears as CannotPullContainerError rather than as an access denied message"

  validation {
    condition     = contains(["AES256", "KMS"], var.encryption_type)
    error_message = "encryption_type must be AES256 or KMS."
  }
}
variable "untagged_image_expiry_days" {
  type        = number
  default     = 1
  description = "How long an untagged image is kept before the lifecycle policy removes it. Every push over a moving tag leaves the previous image tagged with nothing, so without a policy this repository grows by one image per apply forever - which the _monolithic template's bare repository did. Null keeps them all"

  validation {
    condition     = var.untagged_image_expiry_days == null || var.untagged_image_expiry_days >= 1
    error_message = "untagged_image_expiry_days must be at least 1, or null to keep untagged images."
  }
}
