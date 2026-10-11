variable "repository_name" {
  type        = string
  default     = "comfyui-images"
  description = "ECR repository the ComfyUI image is pushed to, comfyui-images as the blueprint named it. The buildspec reads it from the project's IMAGE_REPO_NAME, which is set from this value (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-z0-9]+(?:[._-][a-z0-9]+)*(/[a-z0-9]+(?:[._-][a-z0-9]+)*)*$", var.repository_name)) && length(var.repository_name) <= 256
    error_message = "repository_name must be a valid ECR repository name: lowercase letters, digits and . _ - / separators."
  }
}
variable "base_cache_repository_name" {
  type        = string
  default     = "comfyui-base-cache"
  description = "ECR repository the build mirrors the CUDA base image into on every run, comfyui-base-cache as the blueprint's buildspec named it. The buildspec creates it when it is missing, which would leave a repository outside state that terraform destroy never removes - so it is created here and the buildspec finds it present"

  validation {
    condition     = can(regex("^[a-z0-9]+(?:[._-][a-z0-9]+)*(/[a-z0-9]+(?:[._-][a-z0-9]+)*)*$", var.base_cache_repository_name))
    error_message = "base_cache_repository_name must be a valid ECR repository name."
  }
}
variable "image_tag" {
  type        = string
  default     = "latest"
  description = "Tag the build pushes and the Deployment pulls. latest, as the blueprint had it: the weekly rebuild replaces it in place to pick up base image patches, which is why the Deployment pulls Always. The build also pushes a dated tag next to it"

  validation {
    condition     = can(regex("^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$", var.image_tag))
    error_message = "image_tag must be a valid image tag (letters, digits, _ . -, at most 128 characters)."
  }
}
variable "max_image_count" {
  type        = number
  default     = 10
  description = "How many images each repository keeps before the lifecycle policy expires the oldest, 10 as the blueprint's lifecycleRules had it"

  validation {
    condition     = var.max_image_count >= 1
    error_message = "max_image_count must be at least 1."
  }
}
variable "force_delete" {
  type        = bool
  default     = true
  description = "Whether terraform destroy deletes the repositories while they still hold images. Every image in them was pushed by a build Terraform does not track, so without this destroy stops on RepositoryNotEmptyException. The blueprint retained its repository on stack deletion and deleted it from its destroy script instead"
}
variable "scan_on_push" {
  type        = bool
  default     = true
  description = "Whether ECR runs a basic vulnerability scan on every push, as the blueprint's imageScanOnPush did"
}
variable "project_name" {
  type        = string
  default     = "comfyui-image-build"
  description = "Name of the CodeBuild project, comfyui-image-build as the blueprint named it"

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9_-]{1,254}$", var.project_name))
    error_message = "project_name must be 2-255 characters of letters, digits, hyphens and underscores, starting with a letter or digit."
  }
}
variable "compute_type" {
  type        = string
  default     = "BUILD_GENERAL1_LARGE"
  description = "CodeBuild compute type. LARGE, as the blueprint's ComputeType.LARGE: the build installs PyTorch and ComfyUI's requirements into a CUDA base image, and the layers it pushes run to several gigabytes"

  validation {
    condition     = contains(["BUILD_GENERAL1_SMALL", "BUILD_GENERAL1_MEDIUM", "BUILD_GENERAL1_LARGE", "BUILD_GENERAL1_XLARGE", "BUILD_GENERAL1_2XLARGE"], var.compute_type)
    error_message = "compute_type must be one of the BUILD_GENERAL1_* Linux container compute types."
  }
}
variable "build_image" {
  type        = string
  default     = "aws/codebuild/standard:7.0"
  description = "CodeBuild image the build runs in, standard:7.0 as the blueprint's LinuxBuildImage.STANDARD_7_0"

  validation {
    condition     = length(var.build_image) > 0
    error_message = "build_image must not be empty."
  }
}
variable "build_timeout_minutes" {
  type        = number
  default     = 60
  description = "How long a build may run, 60 minutes as the blueprint had it. The root's build action waits on this number plus a margin for queueing, so the two cannot disagree (rules.md B-5)"

  validation {
    condition     = var.build_timeout_minutes >= 5 && var.build_timeout_minutes <= 2160
    error_message = "build_timeout_minutes must be between 5 and 2160, the range CodeBuild accepts."
  }
}
variable "log_retention_days" {
  type        = number
  default     = 14
  description = "How long the build logs are kept"

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be one of the retention periods CloudWatch Logs accepts."
  }
}
variable "source_bucket_name" {
  type        = string
  description = "Bucket the build context is uploaded to and CodeBuild reads it from"

  validation {
    condition     = length(var.source_bucket_name) >= 3
    error_message = "source_bucket_name must be a bucket name."
  }
}
variable "source_bucket_arn" {
  type        = string
  description = "ARN of source_bucket_name, for scoping the build role's read access to it"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:s3:::", var.source_bucket_arn))
    error_message = "source_bucket_arn must be an S3 bucket ARN."
  }
}
variable "source_object_key" {
  type        = string
  default     = "comfyui-build-source.zip"
  description = "Key the build context is uploaded under"

  validation {
    condition     = endswith(var.source_object_key, ".zip")
    error_message = "source_object_key must end in .zip - CodeBuild unpacks an S3 source as a zip archive."
  }
}
variable "source_zip_path" {
  type        = string
  description = "Local path of the zipped build context - the Dockerfile, the buildspec and the custom nodes. Zipped by the caller rather than here, so the archive is read at plan time even though this module is ordered after the network (rules.md D-6)"

  validation {
    condition     = endswith(var.source_zip_path, ".zip")
    error_message = "source_zip_path must point at a .zip file."
  }
}
variable "source_zip_hash" {
  type        = string
  description = "Base64 SHA-256 of the zip, which is what re-uploads the object when the build context changes. The caller hands the same value to the build trigger and the Deployment's pod template, so an edited Dockerfile is uploaded, built and rolled out by one apply (rules.md B-5)"

  validation {
    condition     = length(var.source_zip_hash) > 0
    error_message = "source_zip_hash must not be empty."
  }
}
variable "rebuild_schedule_expression" {
  type        = string
  default     = "cron(0 3 ? * MON *)"
  description = "EventBridge schedule for the periodic rebuild, Mondays 03:00 UTC as the blueprint's WeeklyImageRebuild rule had it - the buildspec pulls the base image fresh and builds with --no-cache, so a rebuild is how OS patches reach the image. Null drops the rule (rules.md B-4). A rebuild replaces the tag in place; running pods keep the old image until they restart"

  validation {
    condition     = var.rebuild_schedule_expression == null || can(regex("^(cron|rate)\\(.+\\)$", coalesce(var.rebuild_schedule_expression, "rate(1 day)")))
    error_message = "rebuild_schedule_expression must be a cron(...) or rate(...) expression, or null."
  }
}
