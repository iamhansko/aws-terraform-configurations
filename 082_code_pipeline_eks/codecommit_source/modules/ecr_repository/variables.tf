variable "name" {
  type        = string
  description = "Name of the repository. No default: it is derived from the project's name by the caller, and the pipeline's source stage names the same string"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9._/-]{1,255}$", var.name))
    error_message = "name must be 2-256 characters of lowercase letters, digits, dots, underscores, hyphens and slashes."
  }
}
variable "image_tag_mutability" {
  type        = string
  default     = "MUTABLE"
  description = "Whether a tag can be moved to a different image. MUTABLE, because every pipeline run pushes the same tag over the previous image - IMMUTABLE would make the second run fail in its image build stage and the demo would work exactly once"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be MUTABLE or IMMUTABLE."
  }
}
variable "scan_on_push" {
  type        = bool
  default     = true
  description = "Whether ECR scans each pushed image for known vulnerabilities. On, where the _monolithic template left the repository at its defaults. It costs nothing on a basic scan and it is the one thing a registry can tell you about an image you just built"
}
variable "force_delete" {
  type        = bool
  default     = true
  description = "Whether terraform destroy deletes the repository while it still holds images. True, because the pipeline puts images here and a destroy would otherwise stop at RepositoryNotEmptyException with the rest of the stack half removed. Never true for a registry holding anything worth keeping"
}
variable "encryption_type" {
  type        = string
  default     = "AES256"
  description = "How images are encrypted at rest. AES256, which is ECR's own default stated explicitly. KMS would add a key every puller and the pipeline's roles need permission for, which is a second failure surface for no benefit in a demo"

  validation {
    condition     = contains(["AES256", "KMS"], var.encryption_type)
    error_message = "encryption_type must be AES256 or KMS."
  }
}
variable "untagged_image_expiry_days" {
  type        = number
  default     = 1
  description = "How long an untagged image is kept before the lifecycle policy removes it. Every run pushes over the same tag and leaves the previous image untagged, so without a policy this repository grows by one image per pipeline run forever - which the _monolithic template's plain repository did. Set null to keep them all"

  validation {
    condition     = var.untagged_image_expiry_days == null || var.untagged_image_expiry_days >= 1
    error_message = "untagged_image_expiry_days must be at least 1, or null to keep untagged images."
  }
}
