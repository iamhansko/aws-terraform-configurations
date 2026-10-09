variable "connection_name" {
  type        = string
  default     = "github-connection"
  description = "Name of the CodeStar connection, as the _monolithic template named it. Account-and-region unique, and the original did not make it unique per deployment - a second copy of this project in one account fails here with a name conflict"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_.-]{1,32}$", var.connection_name))
    error_message = "connection_name must be 1-32 characters of letters, digits, underscores, dots or hyphens."
  }
}
variable "github_user" {
  type        = string
  description = "GitHub account that owns the repository. The source credential is registered for it and the clone URL is built from it, so one value reaches both (rules.md B-5)"

  validation {
    # No lookahead: Terraform's regex() is Go's RE2, which does not support it, and can() turns the
    # resulting pattern error into a plain false - so the lookahead form rejected every value, valid ones
    # included. See the same variable in the root's variables.tf.
    condition     = can(regex("^[A-Za-z0-9]([A-Za-z0-9-]{0,37}[A-Za-z0-9])?$", var.github_user))
    error_message = "github_user must be a GitHub account name: 1-39 characters of letters, digits and single hyphens, not starting or ending with a hyphen."
  }
}
variable "github_token" {
  type        = string
  sensitive   = true
  description = "GitHub personal access token with repo and workflow scope. sensitive so plan, apply and terraform console do not print it, and no default on purpose - pass it with TF_VAR_github_token. It needs workflow scope as well as repo, because the seed commit the association pushes contains a file under .github/workflows and GitHub rejects that push outright without it"

  validation {
    condition     = can(regex("^(gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{22,})$", var.github_token))
    error_message = "github_token must look like a GitHub personal access token: ghp_/gho_/ghu_/ghs_/ghr_ followed by at least 36 characters, or github_pat_ followed by at least 22."
  }
}
variable "token_parameter_name" {
  type        = string
  description = "Parameter Store path the token is written to as a SecureString, for the seed-commit association to read at runtime rather than carrying the token in its document"

  validation {
    condition     = can(regex("^/[A-Za-z0-9_./-]{1,1000}$", var.token_parameter_name))
    error_message = "token_parameter_name must be an absolute Parameter Store path starting with '/'."
  }
}
variable "bucket_prefix" {
  type        = string
  default     = "github-runner-bucket-"
  description = "Prefix for the generated source bucket name, matching what the _monolithic template built from the stack uuid. The provider appends a unique suffix, which S3 needs because bucket names are globally unique"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,37}$", var.bucket_prefix))
    error_message = "bucket_prefix must be 2-38 characters of lowercase letters, digits, dots and hyphens starting with a letter or digit, leaving room for the suffix the provider appends inside S3's 63-character limit."
  }
}
variable "force_destroy" {
  type        = bool
  default     = true
  description = "Whether terraform destroy may delete the bucket with the uploaded zip still in it. True because the zip is regenerated on every apply and S3 refuses to delete a non-empty bucket, so false turns every destroy into a manual cleanup"
}
