variable "name" {
  type        = string
  description = "Name of the repository"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9._/-]{1,255}$", var.name))
    error_message = "name must start with a lowercase letter or digit and contain only lowercase letters, digits and . _ / -."
  }
}
variable "image_tag" {
  type        = string
  default     = "latest"
  description = "The tag the workbench pushes and the Lambda function is created from. Assembled into image_uri here so the push and the pull cannot name different tags (rules.md B-5)"

  validation {
    condition     = can(regex("^[A-Za-z0-9_][A-Za-z0-9._-]{0,127}$", var.image_tag))
    error_message = "image_tag must be a valid container image tag."
  }
}
variable "image_tag_mutability" {
  type        = string
  default     = "MUTABLE"
  description = "Whether an existing tag can be overwritten. MUTABLE, because this project pushes over one moving tag - see main.tf"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be MUTABLE or IMMUTABLE."
  }
}
variable "force_delete" {
  type        = bool
  default     = true
  description = "Whether terraform destroy deletes the repository while images are still in it. The images are pushed by an instance rather than by Terraform, so without this a destroy stops at RepositoryNotEmptyException"
}
variable "scan_on_push" {
  type        = bool
  default     = false
  description = "Whether ECR runs a basic vulnerability scan on each push"
}
