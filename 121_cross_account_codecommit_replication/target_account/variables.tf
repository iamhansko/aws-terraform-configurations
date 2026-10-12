variable "aws_region" {
  type        = string
  default     = null
  description = "Target-account region. Null follows the AWS provider credential chain."

  validation {
    condition     = var.aws_region == null || can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a region code such as ap-northeast-2, or null to follow the provider chain."
  }
}

variable "target_account_id" {
  type        = string
  description = "Twelve-digit AWS account ID in which this target root must be applied."

  validation {
    condition     = can(regex("^[0-9]{12}$", var.target_account_id))
    error_message = "target_account_id must be a 12-digit AWS account ID."
  }
}

variable "source_account_id" {
  type        = string
  description = "Twelve-digit AWS account ID that owns the replication CodeBuild role."

  validation {
    condition     = can(regex("^[0-9]{12}$", var.source_account_id))
    error_message = "source_account_id must be a 12-digit AWS account ID."
  }

  validation {
    condition     = var.source_account_id != var.target_account_id
    error_message = "source_account_id must differ from target_account_id; use a same-account replication design when both repositories are in one account."
  }
}

variable "target_account_repository" {
  type        = string
  default     = "b-repo"
  description = "CodeCommit repository that receives the mirrored refs. This agreed name must match the source root."

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]{1,100}$", var.target_account_repository))
    error_message = "target_account_repository must be 1-100 characters of letters, digits, dots, underscores, and hyphens."
  }
}

variable "cross_account_role_name" {
  type        = string
  default     = "CrossAccountRole"
  description = "Fixed target role name agreed with the independently applied source root."

  validation {
    condition     = can(regex("^[A-Za-z0-9+=,.@_-]{1,64}$", var.cross_account_role_name))
    error_message = "cross_account_role_name must be 1-64 characters accepted by IAM role names."
  }
}

variable "source_codebuild_role_name" {
  type        = string
  default     = "CodeCommitReplicationBuildRole"
  description = "Exact future CodeBuild role name in the source account, used to constrain the target trust policy."

  validation {
    condition     = can(regex("^[A-Za-z0-9+=,.@_-]{1,64}$", var.source_codebuild_role_name))
    error_message = "source_codebuild_role_name must be 1-64 characters accepted by IAM role names."
  }
}
