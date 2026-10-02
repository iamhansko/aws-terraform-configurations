variable "name" {
  type        = string
  description = "Name of the ECR repository the operator image is pushed to"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9._/-]{1,255}$", var.name))
    error_message = "name must be 2-256 characters of lowercase letters, digits, dots, underscores, hyphens and slashes, starting with a letter or digit - the character set ECR accepts for a repository name."
  }
}
variable "image_tag" {
  type        = string
  default     = "latest"
  description = "Tag the operator image is built and deployed under. One value feeds the docker push and the deployment that pulls it, so the two cannot disagree (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9._-]{0,127}$", var.image_tag))
    error_message = "image_tag must be 1-128 characters of letters, digits, dots, underscores and hyphens, starting with a letter or digit."
  }
}
variable "image_tag_mutability" {
  type        = string
  default     = "MUTABLE"
  description = "Whether an existing tag can be overwritten. MUTABLE, because the demo builds and pushes the same tag repeatedly - IMMUTABLE would reject the second push with ImageTagAlreadyExistsException, and the build step would fail on a re-run rather than on the first one. Worth reversing for anything where knowing which image a tag refers to matters"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be either MUTABLE or IMMUTABLE."
  }
  validation {
    # Cross-variable, available since Terraform 1.9 (rules.md B-1). Neither value is
    # wrong alone, but a floating tag that cannot be overwritten is a build that works
    # exactly once.
    condition     = var.image_tag_mutability == "MUTABLE" || var.image_tag != "latest"
    error_message = "image_tag_mutability cannot be IMMUTABLE while image_tag is \"latest\": the build pushes that tag on every run, and ECR rejects the second push. Pin image_tag to a version instead."
  }
}
variable "scan_on_push" {
  type        = bool
  default     = true
  description = "Whether ECR scans each pushed image for known vulnerabilities. On, because it costs nothing on basic scanning and the operator image is built from a base image nobody here chose deliberately"
}
variable "force_delete" {
  type        = bool
  default     = true
  description = "Whether terraform destroy may delete the repository while images remain in it. True, and load-bearing rather than convenient: the images here are pushed from a build step outside Terraform, so Terraform has nothing in state to remove first. Without this, destroy fails with RepositoryNotEmptyException on a repository Terraform itself created but never put anything into - and the only way forward is deleting the images by hand"
}
variable "encryption_type" {
  type        = string
  default     = "AES256"
  description = "How images are encrypted at rest. AES256 uses keys ECR manages itself and needs no key policy; KMS lets a customer managed key be used, at the cost of granting every puller and every node kms:Decrypt on it"

  validation {
    condition     = contains(["AES256", "KMS"], var.encryption_type)
    error_message = "encryption_type must be either AES256 or KMS."
  }
}
