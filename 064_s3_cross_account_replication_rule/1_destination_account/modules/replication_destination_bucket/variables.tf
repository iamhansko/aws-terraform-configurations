variable "name_prefix" {
  type        = string
  description = "Prefix for the generated bucket name. A prefix rather than a fixed name: bucket names are globally unique. The _monolithic template declared a bare aws_s3_bucket with no arguments, which generates a name and leaves everything else at the provider's defaults"

  validation {
    # 37 is S3's own cap on bucket_prefix, not a margin chosen here - it leaves room for the suffix the
    # service generates. Without this bound the failure is "expected length of bucket_prefix to be in the
    # range (0 - 37)" from the provider, which names neither this variable nor the one that fed it
    # (rules.md B-1).
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,36}$", var.name_prefix))
    error_message = "name_prefix must be 2-37 characters of lowercase letters, digits, dots and hyphens. 37 is S3's limit on a bucket_prefix, which leaves room for the suffix it generates."
  }
}
variable "source_account_id" {
  type        = string
  description = "Account that owns the source bucket and replication role. It forms both the always-existing account-root Principal and the exact role ARN used by the policy condition"

  validation {
    condition     = can(regex("^[0-9]{12}$", var.source_account_id))
    error_message = "source_account_id must be a 12-digit AWS account ID."
  }
}
variable "replication_role_name" {
  type        = string
  description = <<-DESC
    Name of the replication role in the source account. The bucket policy derives the role's full ARN and
    matches it through aws:PrincipalArn.

    A literal name agreed between two roots rather than a value read from the other side, because the two
    accounts have separate state files and neither can reference the other's outputs. The source root
    declares the same string as the name of the role it creates (rules.md I-2).

    The policy's syntactic Principal is arn:aws:iam::<id>:root because the role does not exist during this
    destination-first apply. The ARN condition narrows the grant to only the agreed role, unlike the
    unrestricted account-root policy in the _monolithic template.
  DESC

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,64}$", var.replication_role_name))
    error_message = "replication_role_name must be 1-64 characters from the set IAM accepts for a role name."
  }
}
variable "allow_owner_override" {
  type        = bool
  default     = true
  description = "Whether the replication role may hand ownership of replicated objects to this account. True, and it has to match the source side: cross-account replication otherwise leaves every replicated object owned by the source account, so this account cannot read what is in its own bucket. The source root's replication configuration has to ask for the translation as well - the two together are what make it work, and either one alone does nothing"
}
variable "noncurrent_version_expiration_days" {
  type        = number
  default     = 30
  description = "How long a superseded version is kept. Versioning cannot be turned off on a replication destination, so without a rule every version of every replicated object is retained forever - which is what the _monolithic template left behind. Set null to keep them all"

  validation {
    condition     = var.noncurrent_version_expiration_days == null || var.noncurrent_version_expiration_days >= 1
    error_message = "noncurrent_version_expiration_days must be at least 1, or null to keep every version."
  }
}
variable "force_destroy" {
  type        = bool
  default     = true
  description = "Whether terraform destroy empties the bucket before deleting it. True, because replication puts objects here and a destroy would otherwise stop at BucketNotEmpty. Never true for a bucket holding anything worth keeping"
}
