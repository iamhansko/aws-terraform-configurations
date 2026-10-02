variable "github_user" {
  type        = string
  description = "GitHub username the personal access token belongs to, and the owner of the repository Argo CD is pointed at"

  validation {
    # No lookahead: Terraform's regex is RE2, which has none, and can() would swallow the
    # resulting error and report every value as invalid. Requiring an alphanumeric after each
    # hyphen expresses the same "no trailing or doubled hyphen" rule.
    condition     = can(regex("^[A-Za-z0-9]([A-Za-z0-9]|-[A-Za-z0-9])*$", var.github_user)) && length(var.github_user) <= 39
    error_message = "github_user must be a valid GitHub username: 1-39 characters of letters, digits and single hyphens, not starting or ending with a hyphen."
  }
}
variable "github_token" {
  type        = string
  sensitive   = true
  description = "GitHub personal access token. sensitive so plan and apply do not print it, and no default on purpose. Note the scope of what this creates: a CodeBuild source credential is global per account and region for a given server type, so applying this twice in one account replaces the earlier token rather than failing"

  validation {
    # GitHub's current fine-grained and classic token prefixes. Checking the shape turns a
    # pasted-wrong token into a plan-time error rather than a CodeBuild failure much later
    # (rules.md B-1).
    condition     = can(regex("^(gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{22,})$", var.github_token))
    error_message = "github_token must look like a GitHub personal access token: ghp_/gho_/ghu_/ghs_/ghr_ followed by at least 36 characters, or github_pat_ followed by at least 22. A classic 40-character hex token predates these prefixes and is no longer issued."
  }
}
variable "connection_name" {
  type        = string
  default     = "github-connection"
  description = "Name of the CodeStar connection. Created in PENDING: it only becomes AVAILABLE after someone completes the GitHub handshake in the console, and Terraform reports success either way"

  validation {
    condition     = can(regex("^[A-Za-z0-9_-]{1,32}$", var.connection_name))
    error_message = "connection_name must be 32 characters or fewer of letters, digits, underscores and hyphens, which is what CodeStar accepts."
  }
}
variable "bucket_name" {
  type        = string
  description = "Name of the bucket the seed repository zip is uploaded to. S3 bucket names are globally unique, so the caller derives this from something per-deployment rather than hardcoding it"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "bucket_name must be 3-63 characters of lowercase letters, digits, dots and hyphens, starting and ending alphanumerically."
  }
}
variable "force_destroy" {
  type        = bool
  default     = true
  description = "Whether terraform destroy may delete the bucket while objects remain. True because the only object is a zip regenerated on every apply; a destroy blocked on a non-empty bucket is a worse outcome for a demo than losing that artifact"
}
variable "versioning_enabled" {
  type        = bool
  default     = true
  description = "Whether the bucket keeps object versions. True so an overwritten seed zip is recoverable; the lifecycle rule below stops the old versions accumulating forever"
}
variable "noncurrent_version_expiration_days" {
  type        = number
  default     = 30
  description = "How long superseded versions of the seed zip are kept. Only takes effect while versioning is enabled"

  validation {
    condition     = var.noncurrent_version_expiration_days >= 1
    error_message = "noncurrent_version_expiration_days must be at least 1."
  }
}
