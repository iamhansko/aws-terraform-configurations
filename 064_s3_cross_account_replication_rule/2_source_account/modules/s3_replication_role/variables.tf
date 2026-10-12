variable "role_name" {
  type        = string
  description = <<-DESC
    Name of the role. Fixed rather than generated, which is the opposite of what the rest of this repository
    does, and the exception is the point: the destination account's bucket policy derives this role's ARN
    and matches it through aws:PrincipalArn, while that policy lives in another state file that cannot
    reference this one (rules.md I-2).

    The _monolithic template trusted arn:aws:iam::<source>:root without a condition. The moduleized policy
    retains that always-existing syntactic Principal so destination can apply first, but limits effective
    access to this one role ARN.
  DESC

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,64}$", var.role_name))
    error_message = "role_name must be 1-64 characters from the set IAM accepts for a role name."
  }
}
variable "source_bucket_arn" {
  type        = string
  description = "Bucket the role reads from. Passed in rather than looked up, so the policy is scoped to this bucket - the _monolithic template granted every action on \"*\" (rules.md A-5/B-6)"

  validation {
    condition     = can(regex("^arn:aws:s3:::", var.source_bucket_arn))
    error_message = "source_bucket_arn must be an S3 bucket ARN."
  }
}
variable "destination_bucket_arn" {
  type        = string
  description = "Bucket the role writes into, in the other account. The replicate actions are scoped to this one"

  validation {
    condition     = can(regex("^arn:aws:s3:::", var.destination_bucket_arn))
    error_message = "destination_bucket_arn must be an S3 bucket ARN."
  }
}
variable "allow_owner_override" {
  type        = bool
  default     = true
  description = "Whether the role may hand ownership of replicated objects to the destination account. Has to match the destination bucket policy: this grants the role the action, that policy permits it on the bucket, and the replication configuration asks for the translation - all three or none"
}
variable "inline_policy_name" {
  type        = string
  default     = "S3ReplicationIamPolicy"
  description = "Name of the inline policy, as the _monolithic template named it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,128}$", var.inline_policy_name))
    error_message = "inline_policy_name must be 1-128 characters from the set IAM accepts for a policy name."
  }
}
