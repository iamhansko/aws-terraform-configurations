variable "name" {
  type        = string
  default     = "app-repo"
  description = "Name of the ECR repository, as the _monolithic template had it. The GitHub Actions workflow reads this from the REPOSITORY environment variable"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9._/-]{1,255}$", var.name))
    error_message = "name must start with a lowercase letter or digit and contain only lowercase letters, digits, dots, underscores, hyphens and slashes."
  }
}
variable "image_tag_mutability" {
  type        = string
  default     = "MUTABLE"
  description = "Whether an existing tag can be overwritten. MUTABLE because the demo's workflow reads the tag from a version file that a person edits, and re-running a build without bumping it should not fail"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be either MUTABLE or IMMUTABLE."
  }
}
variable "scan_on_push" {
  type        = bool
  default     = true
  description = "Whether ECR scans images for vulnerabilities on push. Not in the _monolithic template; on here because it costs nothing for basic scanning and the finding shows up next to the image"
}
variable "force_delete" {
  type        = bool
  default     = true
  description = "Whether terraform destroy may delete the repository while it still holds images. True because the demo pushes images into it, and ECR refuses to delete a non-empty repository"
}
variable "max_image_count" {
  type        = number
  default     = 10
  description = "How many images to keep before the lifecycle policy expires the oldest. Null disables the policy entirely, which is what the _monolithic template effectively did"

  validation {
    condition     = var.max_image_count == null || var.max_image_count > 0
    error_message = "max_image_count must be greater than zero, or null to disable the lifecycle policy."
  }
}
