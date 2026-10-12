variable "aws_region" {
  type        = string
  default     = null
  description = "Target AWS region. When null, falls back to the provider default chain (AWS_REGION, profile, etc.)"

  validation {
    condition     = var.aws_region == null || can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a valid AWS region such as ap-northeast-2, or null to fall back to the provider default chain."
  }
}
variable "project_name" {
  type        = string
  default     = "s3-xacct-replication"
  description = "Base name for the bucket prefix. The same default as the source root so the two are recognisably one project in two accounts. Short because S3 caps a bucket_prefix at 37 characters and this root appends \"-destination-\" to it - the fuller \"s3-cross-account-replication\" overflows that, and the provider reports it as a range error on bucket_prefix rather than as anything to do with this variable"

  validation {
    # 24 rather than 63: the module appends "-destination-" and S3 rejects a bucket_prefix over 37 characters
    # (rules.md B-1).
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,23}$", var.project_name))
    error_message = "project_name must be 2-24 characters of lowercase letters, digits and hyphens. The limit is 24 rather than 63 because this root appends \"-destination-\" to it and S3 caps a bucket_prefix at 37 characters."
  }
}
variable "source_account_id" {
  type        = string
  description = "Account that owns the source bucket. No default: it is the other half of this project and there is nothing to guess. This root is applied first, so the value is known before the source account has anything in it - which is why the dependency runs in this direction"

  validation {
    condition     = can(regex("^[0-9]{12}$", var.source_account_id))
    error_message = "source_account_id must be a 12-digit AWS account ID."
  }
}
variable "replication_role_name" {
  type        = string
  default     = "S3CrossAccountReplicationRole"
  description = <<-DESC
    Name of the replication role in the source account. This bucket's policy derives its exact ARN and uses
    it in an aws:PrincipalArn condition.

    Fixed rather than generated, and this is the case where that is right: the two accounts have separate
    state files, so neither root can reference the other's outputs, and a literal string both sides know is
    what breaks the circle (rules.md I-2). The source root declares the same default under the same name.

    The policy uses the source account root as its syntactic Principal because that identity exists before
    this destination-first apply, but the condition prevents every other principal in that account from
    using the grant.
  DESC

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,64}$", var.replication_role_name))
    error_message = "replication_role_name must be 1-64 characters from the set IAM accepts for a role name."
  }
}
variable "allow_owner_override" {
  type        = bool
  default     = true
  description = "Whether the replication role may hand ownership of replicated objects to this account. True, and the source root's replicate_owner_override has to agree: cross-account replication otherwise leaves every object owned by the source account, and nothing in this account can read them"
}
variable "force_destroy" {
  type        = bool
  default     = true
  description = "Whether terraform destroy empties the destination bucket before deleting it. True, because replication puts objects here that Terraform did not create and a destroy would otherwise stop at BucketNotEmpty. The bucket is versioned - S3 requires it on a replication destination - so this removes every version and delete marker as well, and none of it is recoverable (rules.md I-4)"
}
variable "expected_account_id" {
  type        = string
  default     = null
  description = "Account this root expects to be applied into. Null skips this check; the guard against the source account's credentials runs regardless, because source_account_id is required. Set it and a run in any other account fails in plan (rules.md I-2)"

  validation {
    condition     = var.expected_account_id == null || can(regex("^[0-9]{12}$", var.expected_account_id))
    error_message = "expected_account_id must be a 12-digit AWS account ID, or null to skip the check."
  }
}
variable "noncurrent_version_expiration_days" {
  type        = number
  default     = 30
  description = "How long a superseded version of a replicated object is kept. Versioning is mandatory on a replication destination, so without a rule everything is retained forever. Set null to keep them all"

  validation {
    condition     = var.noncurrent_version_expiration_days == null || var.noncurrent_version_expiration_days >= 1
    error_message = "noncurrent_version_expiration_days must be at least 1, or null to keep every version."
  }
}
