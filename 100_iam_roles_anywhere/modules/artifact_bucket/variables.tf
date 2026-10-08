variable "bucket_prefix" {
  type        = string
  default     = "iam-roles-anywhere-"
  description = "Prefix for the generated bucket name. A prefix rather than a fixed name because bucket names are globally unique; the _monolithic template set neither and took the provider's terraform-<timestamp> default (rules.md B-3 for promoting it, main.tf for why a prefix)"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,40}$", var.bucket_prefix))
    error_message = "bucket_prefix must be 2-41 characters of lowercase letters, digits, dots and hyphens, leaving room for the generated suffix inside the 63 character bucket name limit."
  }
}
variable "force_destroy" {
  type        = bool
  default     = true
  description = "Whether terraform destroy empties the bucket before deleting it. True, and not only for convenience: the bootstrap writes four objects Terraform does not track, so a destroy would otherwise stop on BucketNotEmpty and leave an unencrypted private key sitting in the account. Never true for a bucket holding anything worth keeping"
}
variable "sse_algorithm" {
  type        = string
  default     = "AES256"
  description = "Server-side encryption for objects in the bucket. AES256 is SSE-S3 and needs no key to manage; aws:kms would let a key policy limit who can decrypt, which is a real improvement for a bucket holding a private key and is left out here because it adds a KMS key to a demo"

  validation {
    condition     = contains(["AES256", "aws:kms", "aws:kms:dsse"], var.sse_algorithm)
    error_message = "sse_algorithm must be one of AES256, aws:kms, aws:kms:dsse."
  }
}
