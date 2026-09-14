variable "bucket" {
  type        = string
  description = "Name of the S3 bucket the source directory is synced into"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket))
    error_message = "bucket must be a valid S3 bucket name (3-63 lowercase characters, digits, dots and hyphens)."
  }
}

variable "source_dir" {
  type        = string
  description = "Directory whose tree is synced, recursively. Passed straight to 'aws s3 sync' unquoted (see modules/s3_sync_local/main.tf for why), so it must not contain a space; a relative path is resolved against the directory terraform runs in - the caller should prefix it with path.root before passing it here"

  validation {
    condition     = length(var.source_dir) > 0 && !can(regex(" ", var.source_dir))
    error_message = "source_dir must not be empty or contain a space (it is passed to the shell unquoted)."
  }
}

variable "key_prefix" {
  type        = string
  default     = ""
  description = "Prefix prepended to every object key (the destination path segment after the bucket in 'aws s3 sync <dir> s3://<bucket>/<prefix>'). Empty mirrors the directory at the bucket root. Include the trailing slash"

  validation {
    condition     = var.key_prefix == "" || can(regex("^[^/].*/$", var.key_prefix))
    error_message = "key_prefix must be empty, or a path not starting with '/' and ending with '/' (e.g. 'assets/')."
  }
}

variable "file_pattern" {
  type        = string
  default     = "**"
  description = "Glob used only to detect local changes and re-trigger the sync (see local.content_hash below); it does not filter what 'aws s3 sync' itself uploads. Must be '**' (not '*') to recurse: a single '*' matches only entries directly inside source_dir"

  validation {
    condition     = length(var.file_pattern) > 0
    error_message = "file_pattern must not be empty."
  }
}

variable "exclude_patterns" {
  type        = list(string)
  default     = ["**/.DS_Store", ".DS_Store", "**/Thumbs.db", "Thumbs.db"]
  description = "Globs excluded from both the change-detection hash and the sync itself. Each pattern becomes one '--exclude' argument passed to 'aws s3 sync', which is also used to subtract matches out of the fileset used for change detection"
}

variable "delete_removed" {
  type        = bool
  default     = true
  description = "Whether to pass '--delete' to 'aws s3 sync', removing objects under key_prefix that source_dir no longer contains"
}

variable "delete_on_destroy" {
  type        = bool
  default     = true
  description = "Whether terraform destroy runs 'aws s3 rm --recursive' on key_prefix to remove the objects this sync uploaded. Without this the objects survive the destroy and the bucket cannot be removed unless it has force_destroy set"
}

variable "aws_region" {
  type        = string
  default     = null
  description = "Region passed to the AWS CLI via '--region'. When null, the CLI falls back to its own default resolution (AWS_REGION, profile, ~/.aws/config), which may differ from the Terraform provider's region unless they are kept in sync"

  validation {
    condition     = var.aws_region == null || can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a valid AWS region identifier (e.g. us-east-1), or null."
  }
}
