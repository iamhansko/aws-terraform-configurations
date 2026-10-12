variable "repository_name" {
  type        = string
  description = "ECR repository the image is pushed to and the task pulls from"

  validation {
    condition     = can(regex("^[a-z0-9]+(?:[._-][a-z0-9]+)*(/[a-z0-9]+(?:[._-][a-z0-9]+)*)*$", var.repository_name)) && length(var.repository_name) <= 256
    error_message = "repository_name must be a valid ECR repository name: lowercase letters, digits and . _ - / separators."
  }
}
variable "image_tag" {
  type        = string
  description = "Tag the build pushes, the build context's content hash. Content-addressed the way CDK tagged an image asset, so a changed Dockerfile is a new tag and an unchanged one is the same tag"

  validation {
    condition     = can(regex("^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$", var.image_tag))
    error_message = "image_tag must be a valid image tag (letters, digits, _ . -, at most 128 characters)."
  }
}
variable "force_delete" {
  type        = bool
  default     = true
  description = "Whether terraform destroy deletes the repository while it still holds images. Every image in it was pushed by a build, so without this destroy stops on RepositoryNotEmptyException"
}
variable "scan_on_push" {
  type        = bool
  default     = true
  description = "Whether ECR runs a basic vulnerability scan on every push, as the CDK bootstrap repository the blueprint pushed to does"
}
variable "project_name" {
  type        = string
  description = "Name of the CodeBuild project. It also names the log group and prefixes the source bucket, which is why it is lowercase"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,100}$", var.project_name))
    error_message = "project_name must be 2-101 characters of lowercase letters, digits and hyphens - it prefixes an S3 bucket name."
  }
}
variable "compute_type" {
  type        = string
  default     = "BUILD_GENERAL1_MEDIUM"
  description = "CodeBuild compute type. The build compiles Python with pyenv and installs PyTorch into a CUDA base image, and the image it pushes is several gigabytes"

  validation {
    condition     = contains(["BUILD_GENERAL1_SMALL", "BUILD_GENERAL1_MEDIUM", "BUILD_GENERAL1_LARGE", "BUILD_GENERAL1_XLARGE", "BUILD_GENERAL1_2XLARGE"], var.compute_type)
    error_message = "compute_type must be one of the BUILD_GENERAL1_* Linux container compute types."
  }
}
variable "build_image" {
  type        = string
  default     = "aws/codebuild/amazonlinux-x86_64-standard:5.0"
  description = "CodeBuild image the build runs in, the one this project's build used before. Pinned rather than :latest, because a managed image moving under a build changes what it does with no change here"

  validation {
    condition     = can(regex(":[a-zA-Z0-9._-]+$", var.build_image))
    error_message = "build_image must carry an explicit tag."
  }
}
variable "build_timeout_minutes" {
  type        = number
  default     = 90
  description = "How long a build may run. The root's build action waits on this number plus a margin for queueing, so the two cannot disagree (rules.md B-5)"

  validation {
    condition     = var.build_timeout_minutes >= 5 && var.build_timeout_minutes <= 2160
    error_message = "build_timeout_minutes must be between 5 and 2160, the range CodeBuild accepts."
  }
}
variable "buildspec" {
  type        = string
  description = "The build definition, passed in rather than shipped in the build context so that it is not part of the image hash"

  validation {
    condition     = can(regex("(?m)^version:", var.buildspec))
    error_message = "buildspec must declare a version. CodeBuild accepts the project and fails the first build otherwise."
  }
}
variable "log_retention_days" {
  type        = number
  default     = 731
  description = "How long the build logs are kept"

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be one of the retention periods CloudWatch Logs accepts."
  }
}
variable "source_object_key" {
  type        = string
  default     = "comfyui-image-source.zip"
  description = "Key the build context is uploaded under"

  validation {
    condition     = endswith(var.source_object_key, ".zip")
    error_message = "source_object_key must end in .zip - CodeBuild unpacks an S3 source as a zip archive."
  }
}
variable "source_zip_path" {
  type        = string
  description = "Local path of the zipped build context. Zipped by the caller rather than here, so the archive is read at plan even though this module is ordered after the network (rules.md D-6)"

  validation {
    condition     = endswith(var.source_zip_path, ".zip")
    error_message = "source_zip_path must point at a .zip file."
  }
}
variable "source_hash" {
  type        = string
  description = "Content hash of the build context, which is what uploads the object again when a file in it changes"

  validation {
    condition     = length(var.source_hash) > 0
    error_message = "source_hash must not be empty."
  }
}
