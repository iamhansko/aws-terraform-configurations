variable "partition" {
  type        = string
  description = "AWS partition used to construct IAM and service ARNs."

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.partition))
    error_message = "partition must be a valid AWS partition such as aws or aws-us-gov."
  }
}

variable "dns_suffix" {
  type        = string
  description = "AWS partition DNS suffix used in regional CodeCommit HTTPS URLs."

  validation {
    condition     = can(regex("^[A-Za-z0-9.-]+$", var.dns_suffix))
    error_message = "dns_suffix must be a DNS suffix such as amazonaws.com."
  }
}

variable "source_account_id" {
  type        = string
  description = "Account ID that owns the source repository and pipeline."

  validation {
    condition     = can(regex("^[0-9]{12}$", var.source_account_id))
    error_message = "source_account_id must be a 12-digit AWS account ID."
  }
}

variable "source_region" {
  type        = string
  description = "Region containing the source repository and build."

  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.source_region))
    error_message = "source_region must be a valid AWS region code."
  }
}

variable "target_account_id" {
  type        = string
  description = "Account ID containing the target repository and role."

  validation {
    condition     = can(regex("^[0-9]{12}$", var.target_account_id))
    error_message = "target_account_id must be a 12-digit AWS account ID."
  }

  validation {
    condition     = var.target_account_id != var.source_account_id
    error_message = "target_account_id must differ from source_account_id."
  }
}

variable "target_region" {
  type        = string
  description = "Region containing the target CodeCommit repository."

  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.target_region))
    error_message = "target_region must be a valid AWS region code."
  }
}

variable "source_account_repository" {
  type        = string
  description = "Name of the source CodeCommit repository."

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]{1,100}$", var.source_account_repository))
    error_message = "source_account_repository must be 1-100 CodeCommit-compatible characters."
  }
}

variable "target_account_repository" {
  type        = string
  description = "Name of the independently created target CodeCommit repository."

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]{1,100}$", var.target_account_repository))
    error_message = "target_account_repository must be 1-100 CodeCommit-compatible characters."
  }
}

variable "cross_account_role_name" {
  type        = string
  description = "Fixed target role name independently agreed by the two roots."

  validation {
    condition     = can(regex("^[A-Za-z0-9+=,.@_-]{1,64}$", var.cross_account_role_name))
    error_message = "cross_account_role_name must be 1-64 characters accepted by IAM role names."
  }
}

variable "source_codebuild_role_name" {
  type        = string
  description = "Fixed CodeBuild role name named in the target trust condition."

  validation {
    condition     = can(regex("^[A-Za-z0-9+=,.@_-]{1,64}$", var.source_codebuild_role_name))
    error_message = "source_codebuild_role_name must be 1-64 characters accepted by IAM role names."
  }
}

variable "main_branch" {
  type        = string
  description = "Branch whose creation and updates start the pipeline."

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9._/-]{0,254}$", var.main_branch)) && !strcontains(var.main_branch, "..") && !strcontains(var.main_branch, "@{") && !endswith(var.main_branch, "/") && !endswith(var.main_branch, ".")
    error_message = "main_branch must be a plain Git branch name without '..', '@{', or a trailing slash/dot."
  }
}

variable "project_name" {
  type        = string
  description = "Prefix for generated same-account IAM role names."

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,39}$", var.project_name))
    error_message = "project_name must be 2-40 lowercase letters, digits, or hyphens."
  }
}

variable "pipeline_name" {
  type        = string
  description = "Name of the replication CodePipeline pipeline."

  validation {
    condition     = can(regex("^[A-Za-z0-9.@_-]{1,100}$", var.pipeline_name))
    error_message = "pipeline_name must be 1-100 characters accepted by CodePipeline."
  }
}

variable "build_project_name" {
  type        = string
  description = "Name of the CodeBuild mirror project."

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9_-]{1,254}$", var.build_project_name))
    error_message = "build_project_name must be 2-255 characters accepted by CodeBuild."
  }
}

variable "event_rule_name" {
  type        = string
  description = "Name of the EventBridge source-branch trigger."

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]{1,64}$", var.event_rule_name))
    error_message = "event_rule_name must be 1-64 characters accepted by EventBridge."
  }
}

variable "artifact_bucket_prefix" {
  type        = string
  description = "Prefix for the generated pipeline artifact bucket."

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,35}[a-z0-9-]$", var.artifact_bucket_prefix)) && !strcontains(var.artifact_bucket_prefix, "--")
    error_message = "artifact_bucket_prefix must be 2-37 lowercase letters, digits, or hyphens."
  }
}

variable "codebuild_image" {
  type        = string
  description = "Pinned managed CodeBuild image with Git and AWS CLI already installed."

  validation {
    condition     = var.codebuild_image == "aws/codebuild/standard:7.0"
    error_message = "codebuild_image must stay aws/codebuild/standard:7.0. The buildspec relies on its bundled Git, Bash, and AWS CLI and intentionally performs no network installs."
  }
}

variable "codebuild_compute_type" {
  type        = string
  description = "CodeBuild compute size."

  validation {
    condition     = contains(["BUILD_GENERAL1_SMALL", "BUILD_GENERAL1_MEDIUM", "BUILD_GENERAL1_LARGE"], var.codebuild_compute_type)
    error_message = "codebuild_compute_type must be a supported BUILD_GENERAL1 Linux container size."
  }
}

variable "build_timeout_minutes" {
  type        = number
  description = "Maximum build duration in minutes."

  validation {
    condition     = var.build_timeout_minutes >= 5 && var.build_timeout_minutes <= 2160
    error_message = "build_timeout_minutes must be between 5 and 2160."
  }
}

variable "build_log_retention_days" {
  type        = number
  description = "CloudWatch Logs retention for build output."

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.build_log_retention_days)
    error_message = "build_log_retention_days must be a retention period CloudWatch Logs accepts."
  }
}

variable "initial_commit_file_path" {
  type        = string
  description = "Repository-relative file path used to create main_branch before the pipeline exists."

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9._/-]{0,255}$", var.initial_commit_file_path)) && alltrue([for segment in split("/", var.initial_commit_file_path) : !contains(["", ".", ".."], segment)])
    error_message = "initial_commit_file_path must be a 1-256 character safe relative path without empty, '.' or '..' segments."
  }
}

variable "initial_commit_file_content" {
  type        = string
  description = "Non-empty content written by the source repository's create-only initial commit."

  validation {
    condition     = length(trimspace(var.initial_commit_file_content)) > 0 && length(var.initial_commit_file_content) <= 8192
    error_message = "initial_commit_file_content must contain 1-8192 characters and must not be only whitespace."
  }
}

variable "initial_commit_message" {
  type        = string
  description = "Message for the create-only commit that establishes main_branch."

  validation {
    condition     = length(trimspace(var.initial_commit_message)) > 0 && length(var.initial_commit_message) <= 256
    error_message = "initial_commit_message must contain 1-256 characters and must not be only whitespace."
  }
}

variable "pipeline_role_propagation_wait_seconds" {
  type        = number
  default     = 30
  description = "Whole seconds to wait for the CodePipeline role policy to reach the CodePipeline service before pipeline creation."

  validation {
    condition     = var.pipeline_role_propagation_wait_seconds >= 0 && floor(var.pipeline_role_propagation_wait_seconds) == var.pipeline_role_propagation_wait_seconds
    error_message = "pipeline_role_propagation_wait_seconds must be a whole number of seconds, zero or greater."
  }
}
