variable "project_name" {
  type        = string
  default     = "comfyui-model-download"
  description = "Name of the CodeBuild project, comfyui-model-download as the blueprint named it"

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9_-]{1,254}$", var.project_name))
    error_message = "project_name must be 2-255 characters of letters, digits, hyphens and underscores, starting with a letter or digit."
  }
}
variable "buildspec" {
  type        = string
  description = "The download script as a CodeBuild buildspec, read by the caller from buildspec/models.yml. Inline in the project rather than shipped as a source zip the way the blueprint did, because it is the whole of the build's input and fits in the project definition"

  validation {
    condition     = startswith(trimspace(var.buildspec), "version:")
    error_message = "buildspec must be a CodeBuild buildspec document, starting with its version: key."
  }
}
variable "models_bucket_name" {
  type        = string
  description = "Bucket the models are written to - the one the GPU nodes copy from at boot and the sync Lambda watches"

  validation {
    condition     = length(var.models_bucket_name) >= 3
    error_message = "models_bucket_name must be a bucket name."
  }
}
variable "models_bucket_arn" {
  type        = string
  description = "ARN of models_bucket_name, for scoping the build role to it"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:s3:::", var.models_bucket_arn))
    error_message = "models_bucket_arn must be an S3 bucket ARN."
  }
}
variable "model_tier" {
  type        = string
  default     = "all"
  description = "Which models the build downloads: tier1 for the four files the default workflow needs, all for the full set, as the blueprint's MODEL_TIER. all, which is what the blueprint's project defaulted to. The download skips files already in the bucket, so re-running it is cheap"

  validation {
    condition     = contains(["tier1", "all"], var.model_tier)
    error_message = "model_tier must be tier1 or all."
  }
}
variable "compute_type" {
  type        = string
  default     = "BUILD_GENERAL1_LARGE"
  description = "CodeBuild compute type, LARGE as the blueprint had it. Disk matters more than CPU here: each model is downloaded to local disk before it is copied to S3, and the largest is tens of gigabytes"

  validation {
    condition     = contains(["BUILD_GENERAL1_SMALL", "BUILD_GENERAL1_MEDIUM", "BUILD_GENERAL1_LARGE", "BUILD_GENERAL1_XLARGE", "BUILD_GENERAL1_2XLARGE"], var.compute_type)
    error_message = "compute_type must be one of the BUILD_GENERAL1_* Linux container compute types."
  }
}
variable "build_image" {
  type        = string
  default     = "aws/codebuild/standard:7.0"
  description = "CodeBuild image the download runs in, standard:7.0 as the blueprint had it"

  validation {
    condition     = length(var.build_image) > 0
    error_message = "build_image must not be empty."
  }
}
variable "build_timeout_minutes" {
  type        = number
  default     = 240
  description = "How long the download may run, four hours as the blueprint had it. The full set is several hundred gigabytes pulled from HuggingFace one file at a time"

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
