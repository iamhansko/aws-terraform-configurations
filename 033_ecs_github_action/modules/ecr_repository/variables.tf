variable "name" {
  type        = string
  default     = "ecs-cicd-ecr"
  description = "Name of the repository, as the _monolithic template named it"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9._/-]{1,255}$", var.name))
    error_message = "name must be 2-256 characters of lowercase letters, digits, dots, underscores, hyphens or slashes, starting with a letter or digit, which is what ECR accepts."
  }
}
variable "image_tag" {
  type        = string
  default     = "latest"
  description = "The moving tag the workbench pushes and the task definition pulls. The GitHub Actions workflow pushes both this tag and the commit sha on every run"

  validation {
    condition     = can(regex("^[A-Za-z0-9_][A-Za-z0-9._-]{0,127}$", var.image_tag))
    error_message = "image_tag must be 1-128 characters of letters, digits, dots, underscores or hyphens, starting with a letter, digit or underscore."
  }
}
variable "image_tag_mutability" {
  type        = string
  default     = "MUTABLE"
  description = "Whether a tag can be moved to a different image. MUTABLE is required here: the workbench pushes image_tag once and the workflow overwrites it on every run"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be MUTABLE or IMMUTABLE."
  }
  validation {
    condition     = var.image_tag_mutability == "MUTABLE"
    error_message = "image_tag_mutability must stay MUTABLE in this project. Both the workbench and the GitHub Actions workflow push over the same moving tag, and IMMUTABLE makes the second push fail with ImageTagAlreadyExistsException - in the workflow that surfaces as a failed job rather than as a Terraform error."
  }
}
variable "force_delete" {
  type        = bool
  default     = true
  description = "Whether terraform destroy may delete the repository with images still in it. True because the repository is never empty by then - the workbench pushes one image and the workflow pushes one per run - and ECR refuses to delete a non-empty repository, so false turns every destroy into a manual cleanup"
}
variable "scan_on_push" {
  type        = bool
  default     = true
  description = "Whether ECR scans each pushed image for vulnerabilities. The _monolithic template left this at the account default"
}
variable "encryption_type" {
  type        = string
  default     = "AES256"
  description = "Encryption applied to images at rest"

  validation {
    condition     = contains(["AES256", "KMS"], var.encryption_type)
    error_message = "encryption_type must be AES256 or KMS."
  }
}
variable "untagged_image_expiry_days" {
  type        = number
  default     = 1
  description = "Days an untagged image is kept before the lifecycle policy expires it. Null removes the policy entirely"

  validation {
    condition     = var.untagged_image_expiry_days == null || var.untagged_image_expiry_days >= 1
    error_message = "untagged_image_expiry_days must be at least 1, or null to create no lifecycle policy."
  }
}
