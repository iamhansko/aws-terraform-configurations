variable "name" {
  type        = string
  description = "Name of the repository. CloudFormation would have generated one; Terraform requires it, so the caller builds it from the project name"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9._/-]{1,255}$", var.name))
    error_message = "name must be 2-256 characters, start with a lowercase letter or digit, and otherwise contain only lowercase letters, digits, dots, underscores, hyphens and slashes - the character set ECR accepts for a repository name."
  }
}
variable "seed_image_tag" {
  type        = string
  default     = "prototype"
  description = "Tag the bastion pushes the first image under, and the tag the task definition this apply registers pulls. Re-exposed as an output so the push and the pull are one value (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9._-]{0,127}$", var.seed_image_tag))
    error_message = "seed_image_tag must be 1-128 characters, start with a letter or digit, and otherwise contain only letters, digits, dots, underscores and hyphens."
  }
}
variable "image_tag_mutability" {
  type        = string
  default     = "MUTABLE"
  description = "Whether a tag in this repository can be moved to a different image. MUTABLE so that re-applying, which re-runs the bastion userdata, can push the seed tag again"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be MUTABLE or IMMUTABLE."
  }
}
variable "force_delete" {
  type        = bool
  default     = true
  description = "Whether to delete the repository together with the images in it. True as the _monolithic template set it, and required here: the repository is never empty by the time a destroy reaches it, and ECR rejects deleting a repository that holds images"
}
variable "scan_on_push" {
  type        = bool
  default     = false
  description = "Whether to scan each pushed image for vulnerabilities. Off, which is what the _monolithic template's bare repository got by default - the seed image is a golang base image built on every apply and the findings would be the base image's, not this project's"
}
variable "encryption_type" {
  type        = string
  default     = "AES256"
  description = "Server-side encryption applied to the stored layers"

  validation {
    condition     = contains(["AES256", "KMS", "KMS_DSSE"], var.encryption_type)
    error_message = "encryption_type must be AES256, KMS or KMS_DSSE. KMS and KMS_DSSE also need a key, which this module does not take - there is nothing in this project a customer managed key would protect that AES256 does not."
  }
}
