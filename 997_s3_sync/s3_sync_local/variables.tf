variable "aws_region" {
  type        = string
  default     = null
  description = "Target AWS region. When null, falls back to the provider default chain (AWS_REGION, profile, etc.)"

  validation {
    condition     = var.aws_region == null || can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a valid AWS region identifier (e.g. us-east-1), or null."
  }
}

variable "source_dir" {
  type        = string
  default     = "../src"
  description = "Directory whose tree is uploaded, relative to this root module. Defaults to the src/ directory shared by the variants in this project. Exposed as a variable so a copy of this variant can point at its own directory instead of depending on a sibling path"

  validation {
    condition     = length(var.source_dir) > 0
    error_message = "source_dir must not be empty."
  }
}

variable "bucket_name" {
  type        = string
  default     = null
  description = "Explicit target bucket name. When null, a unique name is generated from bucket_name_prefix, since the S3 bucket namespace is global"

  validation {
    condition     = var.bucket_name == null || can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "bucket_name must be a valid S3 bucket name (3-63 lowercase characters, digits, dots and hyphens), or null."
  }
}

variable "bucket_name_prefix" {
  type        = string
  default     = "s3-sync-local-"
  description = "Prefix for the generated bucket name, used when bucket_name is null"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{0,36}$", var.bucket_name_prefix))
    error_message = "bucket_name_prefix must be 37 characters or fewer of lowercase letters, digits, dots and hyphens, starting with a letter or digit."
  }
}

variable "force_destroy" {
  type        = bool
  default     = true
  description = "Whether terraform destroy may delete the bucket while it still holds objects"
}

variable "key_prefix" {
  type        = string
  default     = ""
  description = "Prefix prepended to every object key. Empty mirrors the directory at the bucket root, i.e. src/1/1-1.txt becomes s3://<bucket>/1/1-1.txt. Set something like \"src/\" to keep the directory name in the key. Include the trailing slash"

  validation {
    condition     = var.key_prefix == "" || can(regex("^[^/].*/$", var.key_prefix))
    error_message = "key_prefix must be empty, or a path not starting with '/' and ending with '/' (e.g. 'src/')."
  }
}

variable "delete_removed" {
  type        = bool
  default     = true
  description = "Whether objects the source directory no longer contains are deleted from the bucket, the equivalent of 'aws s3 sync --delete'"
}

variable "delete_on_destroy" {
  type        = bool
  default     = true
  description = "Whether terraform destroy runs 'aws s3 rm --recursive' to remove the objects this sync uploaded, rather than relying on the bucket's force_destroy to sweep them"
}

variable "exclude_patterns" {
  type        = list(string)
  default     = ["**/.DS_Store", ".DS_Store", "**/Thumbs.db", "Thumbs.db"]
  description = "Globs excluded from the upload, the equivalent of 'aws s3 sync --exclude'"
}
