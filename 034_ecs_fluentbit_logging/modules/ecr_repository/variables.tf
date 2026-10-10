variable "name" {
  type        = string
  description = "Name of the repository. No default: the root derives both repository names from the project name, because the _monolithic template named them as literals"
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9._/-]{1,255}$", var.name))
    error_message = "name must be 2-256 characters of lowercase letters, digits, dots, underscores, hyphens and slashes, starting with a letter or digit. An uppercase letter is rejected by ECR at apply time with InvalidParameterException, not by plan."
  }
}
variable "image_tag" {
  type        = string
  default     = "v1.0.0"
  description = "The tag the build pushes and the task definition pulls, as the _monolithic template tagged both images. One value, re-exposed as an output, so the push and the pull cannot name different tags - a mismatch is not an error anywhere, it is a service whose tasks stop with CannotPullContainerError while the image sits in the repository under another tag (rules.md B-5)"
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9._-]{0,127}$", var.image_tag))
    error_message = "image_tag must be 1-128 characters of letters, digits, dots, underscores and hyphens, starting with a letter or digit."
  }
}
variable "image_tag_mutability" {
  type        = string
  default     = "MUTABLE"
  description = <<-DESC
    Whether a tag can be moved to a different image.
    The _monolithic template set IMMUTABLE on both repositories. That is changed here, because the build
    is a State Manager association rather than something a person runs once: any edit to the build script
    changes the association's parameters, Systems Manager re-runs it, and the second push of v1.0.0 comes
    back as ImageTagAlreadyExistsException. The association then reports Failed and the apply fails on a
    line about an image tag, several resources away from the script that was edited.
    IMMUTABLE is the right setting for a registry that a release pipeline writes to once per version. It
    is the wrong one for a fixed tag that a bootstrap re-pushes.
  DESC
  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be MUTABLE or IMMUTABLE."
  }
}
variable "force_delete" {
  type        = bool
  default     = true
  description = "Whether terraform destroy deletes the repository while it still holds images. The _monolithic template left this at its default of false, which means destroy stops at RepositoryNotEmptyException - the build always puts an image here, so that is not an edge case but the only outcome. Never true for a registry holding anything worth keeping"
}
variable "scan_on_push" {
  type        = bool
  default     = true
  description = "Whether ECR scans each pushed image for known vulnerabilities, as the _monolithic template set it"
}
variable "encryption_type" {
  type        = string
  default     = "AES256"
  description = "How images are encrypted at rest, as the _monolithic template set it. KMS would add a key the container instance role and the task execution role both have to be allowed to use, and a missing grant there appears as CannotPullContainerError rather than as an access denied message"
  validation {
    condition     = contains(["AES256", "KMS"], var.encryption_type)
    error_message = "encryption_type must be AES256 or KMS."
  }
}
variable "untagged_image_expiry_days" {
  type        = number
  default     = 1
  description = "How long an untagged image is kept before the lifecycle policy removes it. With a mutable tag, every re-push leaves the previous image tagged with nothing, so without a policy this repository grows by one image per build forever. Null keeps them all"
  validation {
    condition     = var.untagged_image_expiry_days == null || var.untagged_image_expiry_days >= 1
    error_message = "untagged_image_expiry_days must be at least 1, or null to keep untagged images."
  }
}
