variable "name" {
  type        = string
  description = "Repository name. The _monolithic template used the bare stack keys, green and red, which are account and region wide - a second copy of this project collides with RepositoryAlreadyExistsException, and the repository name is also baked into the image reference in the task definition and in the build step"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9._/-]{1,255}$", var.name))
    error_message = "name must start with a lowercase letter or digit and contain only lowercase letters, digits and the set ._/- that ECR accepts in a repository name."
  }
}
variable "encryption_type" {
  type        = string
  description = "Encryption at rest. One of the genuine differences between the two stacks in this project: the _monolithic template left green on AES256 and put red on the customer managed key"

  validation {
    condition     = contains(["AES256", "KMS"], var.encryption_type)
    error_message = "encryption_type must be AES256 or KMS."
  }
}
variable "kms_key_arn" {
  type        = string
  default     = null
  description = "Key used when encryption_type is KMS, ignored otherwise. Null means ECR uses its AWS managed key"

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN, or null."
  }
  validation {
    # Cross-variable condition (rules.md B-1). The constraint is about the pair, and getting it
    # wrong in this direction is the quiet one: a key passed with AES256 would simply be dropped,
    # so the repository is created unencrypted by the project key and nothing says so.
    condition     = var.encryption_type != "KMS" || var.kms_key_arn != null
    error_message = "kms_key_arn is required when encryption_type is KMS. Set encryption_type to AES256 to use ECR's own encryption instead."
  }
}
variable "scan_on_push" {
  type        = bool
  description = "Whether ECR scans an image when it is pushed. The _monolithic template enabled it on both repositories"
}
variable "image_tag_mutability" {
  type        = string
  description = "Whether a tag can be moved to a different image. IMMUTABLE in the _monolithic template, which is why the image build step has to check for a tag before pushing it - see main.tf"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE", "MUTABLE_WITH_EXCLUSION", "IMMUTABLE_WITH_EXCLUSION"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be MUTABLE, IMMUTABLE, MUTABLE_WITH_EXCLUSION or IMMUTABLE_WITH_EXCLUSION."
  }
}
variable "force_delete" {
  type        = bool
  description = "Whether terraform destroy deletes the repository with its images still in it. True here: the build step pushes two tags into each repository, and ECR refuses to delete a non-empty one - which stops the destroy with RepositoryNotEmptyException. Never true for a repository holding anything worth keeping"
}
