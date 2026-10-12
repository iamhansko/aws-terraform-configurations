variable "partition" {
  type        = string
  description = "AWS partition used to construct cross-account IAM ARNs."

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.partition))
    error_message = "partition must be a valid AWS partition such as aws or aws-us-gov."
  }
}

variable "target_account_id" {
  type        = string
  description = "Account ID that owns the target repository and role."

  validation {
    condition     = can(regex("^[0-9]{12}$", var.target_account_id))
    error_message = "target_account_id must be a 12-digit AWS account ID."
  }
}

variable "source_account_id" {
  type        = string
  description = "Account ID that will create the trusted CodeBuild role."

  validation {
    condition     = can(regex("^[0-9]{12}$", var.source_account_id))
    error_message = "source_account_id must be a 12-digit AWS account ID."
  }

  validation {
    condition     = var.source_account_id != var.target_account_id
    error_message = "source_account_id must differ from target_account_id."
  }
}

variable "target_account_repository" {
  type        = string
  description = "Name of the target CodeCommit repository."

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]{1,100}$", var.target_account_repository))
    error_message = "target_account_repository must be 1-100 characters of letters, digits, dots, underscores, and hyphens."
  }
}

variable "cross_account_role_name" {
  type        = string
  description = "Fixed role name independently agreed with the source root."

  validation {
    condition     = can(regex("^[A-Za-z0-9+=,.@_-]{1,64}$", var.cross_account_role_name))
    error_message = "cross_account_role_name must be 1-64 characters accepted by IAM role names."
  }
}

variable "source_codebuild_role_name" {
  type        = string
  description = "Exact CodeBuild role name that the trust-policy condition permits."

  validation {
    condition     = can(regex("^[A-Za-z0-9+=,.@_-]{1,64}$", var.source_codebuild_role_name))
    error_message = "source_codebuild_role_name must be 1-64 characters accepted by IAM role names."
  }
}
