variable "repository_name" {
  type        = string
  default     = "eks-mcp-server"
  description = "Name of the ECR repository the image is pushed to, as the _monolithic template named it"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9._/-]*[a-z0-9])?$", var.repository_name))
    error_message = "repository_name must be lowercase letters, digits, dots, underscores, slashes and hyphens."
  }
}

variable "project_name" {
  type        = string
  default     = "image-builder"
  description = "Name of the CodeBuild project, as the _monolithic template named it. Also the log group path"

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9_-]{1,254}$", var.project_name))
    error_message = "project_name must be 2-255 characters of letters, digits, underscores and hyphens."
  }
}

variable "dockerfile" {
  type        = string
  description = "Contents of the Dockerfile, read by the caller with file(). Passed in rather than written inline so it lives as a real file the caller can lint - the build has no source repository to read it from, which is why it travels inside the buildspec at all. It is base64-encoded on the way in, so any content is safe here: indentation, YAML-looking lines, shell metacharacters and heredoc delimiters all survive (see main.tf for the failure that taught this)"

  validation {
    condition     = can(regex("(?i)^\\s*(#|FROM)", var.dockerfile))
    error_message = "dockerfile must look like a Dockerfile - it has to start with a comment or a FROM instruction."
  }
  # There was a second validation here forbidding the string TFDOCKERFILE, which was the shell
  # heredoc delimiter the buildspec used to write this value out. The buildspec no longer uses a
  # heredoc - the content is base64-encoded onto a single line - so there is no delimiter left to
  # collide with and the rule had nothing to protect.
}

variable "image_tag" {
  type        = string
  default     = "latest"
  description = "Tag the built image is pushed with, as the _monolithic template used. latest is what makes imagePullPolicy: Always meaningful in the workload - and also what makes it impossible to say which build a running pod came from"

  validation {
    condition     = can(regex("^[A-Za-z0-9_][A-Za-z0-9._-]{0,127}$", var.image_tag))
    error_message = "image_tag must be a valid container image tag."
  }
}

variable "image_tag_mutability" {
  type        = string
  default     = "MUTABLE"
  description = "Whether a tag can be moved to a different image. MUTABLE, because the build pushes the same tag every time - IMMUTABLE would make the second build fail on the push"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be either MUTABLE or IMMUTABLE."
  }
}

variable "force_delete" {
  type        = bool
  default     = true
  description = "Whether terraform destroy deletes the repository along with the images in it. True: every image in here was pushed by a build Terraform does not track, so without it destroy stops on a repository it cannot empty"
}

variable "scan_on_push" {
  type        = bool
  default     = true
  description = "Whether ECR scans each pushed image for known vulnerabilities. True, which the _monolithic template left off"
}

variable "compute_type" {
  type        = string
  default     = "BUILD_GENERAL1_MEDIUM"
  description = "CodeBuild compute size, as the _monolithic template set it"

  validation {
    condition = contains([
      "BUILD_GENERAL1_SMALL", "BUILD_GENERAL1_MEDIUM", "BUILD_GENERAL1_LARGE", "BUILD_GENERAL1_XLARGE", "BUILD_GENERAL1_2XLARGE",
    ], var.compute_type)
    error_message = "compute_type must be one of the BUILD_GENERAL1_* sizes."
  }
}

variable "build_image" {
  type        = string
  default     = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
  description = "CodeBuild build image, as the _monolithic template chose"

  validation {
    condition     = length(var.build_image) > 0
    error_message = "build_image must not be empty."
  }
}

variable "build_timeout_minutes" {
  type        = number
  default     = 30
  description = "How long a build may run, as the _monolithic template set it. The image installs a Python toolchain and a package from PyPI, so it is not a fast build"

  validation {
    condition     = var.build_timeout_minutes >= 5 && var.build_timeout_minutes <= 480
    error_message = "build_timeout_minutes must be between 5 and 480."
  }
}

variable "log_retention_days" {
  type        = number
  default     = 14
  description = "Retention on the build log group. The _monolithic template let CodeBuild create the group implicitly, which means never expiring"

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be one of the retention values CloudWatch Logs accepts."
  }
}
