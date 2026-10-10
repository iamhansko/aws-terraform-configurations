variable "name" {
  type        = string
  description = "Name of the repository. No default: the root derives one per application, as the _monolithic template named them user, product and stress"
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9._/-]{1,255}$", var.name))
    error_message = "name must be 2-256 characters of lowercase letters, digits, dots, underscores, hyphens and slashes, starting with a letter or digit. An uppercase letter is rejected by ECR at apply with InvalidParameterException, not by plan."
  }
}
variable "image_tag" {
  type        = string
  default     = "latest"
  description = <<-DESC
    The tag the build pushes and the task definition pulls.

    One value, re-exposed as an output, so the two cannot name different tags (rules.md B-5). A mismatch is
    not an error anywhere: the image sits in the repository under one tag while the service's tasks stop
    with CannotPullContainerError looking for another.

    The _monolithic template's build commands were "docker build -t ${"$"}{UserEcr.RepositoryUri} ." with no tag
    at all, which docker resolves to :latest - so latest is what it meant.
  DESC
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9._-]{0,127}$", var.image_tag))
    error_message = "image_tag must be 1-128 characters of letters, digits, dots, underscores and hyphens, starting with a letter or digit."
  }
}
variable "image_tag_mutability" {
  type        = string
  default     = "MUTABLE"
  description = "Whether a tag can be moved to a different image. MUTABLE, because a build can push a tag that already exists: over the moving \"latest\" this module defaults to on every build, and over a source-digest tag (what this root passes) whenever unchanged source is built again, such as a replaced workbench re-running its build associations. Go builds are not byte-reproducible, so that is a different image under the same tag, and IMMUTABLE fails the push - inside an SSM association, so it surfaces as a service that never pulls rather than as a Terraform error"
  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be MUTABLE or IMMUTABLE."
  }
}
variable "force_delete" {
  type        = bool
  default     = true
  description = "Whether terraform destroy deletes the repository while it still holds images. True, as the _monolithic template had it - and it matters more here than it did there, because here there actually are images: without it destroy stops at RepositoryNotEmptyException with the cluster already gone"
}
variable "scan_on_push" {
  type        = bool
  default     = true
  description = "Whether ECS scans each pushed image for known vulnerabilities. On, where the template left the repository at its defaults. A basic scan costs nothing and the runtime layer here is amazonlinux:2023, which accumulates findings between builds"
}
variable "untagged_image_expiry_days" {
  type        = number
  default     = 1
  description = "How long an untagged image is kept before the lifecycle policy removes it. Every push over a moving tag leaves the previous image tagged with nothing, so without a policy the repository grows by one image per apply forever. Null keeps them all"
  validation {
    condition     = var.untagged_image_expiry_days == null || var.untagged_image_expiry_days >= 1
    error_message = "untagged_image_expiry_days must be at least 1, or null to keep untagged images."
  }
}
