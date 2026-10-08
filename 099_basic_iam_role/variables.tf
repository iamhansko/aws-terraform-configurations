variable "aws_region" {
  type        = string
  default     = null
  description = "Target AWS region. When null, falls back to the provider default chain (AWS_REGION, profile, etc.). IAM itself is global, so this only decides which endpoint the calls go to"

  validation {
    condition     = var.aws_region == null || can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a valid AWS region such as ap-northeast-2, or null to fall back to the provider default chain."
  }
}
variable "project_name" {
  type        = string
  default     = "basic-iam-role"
  description = "Base name for the three roles. One value rather than a name per role, so a second copy of this project in the same account does not collide"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,24}$", var.project_name))
    error_message = "project_name must be 2-25 characters of lowercase letters, digits and hyphens, short enough to leave room for the per-role suffix inside an IAM role name."
  }
}
variable "trusted_service" {
  type        = string
  default     = "ec2.amazonaws.com"
  description = "Service principal allowed to assume all three roles, ec2.amazonaws.com as the _monolithic template had it. One value feeds all three documents, because the three differing only in how they are written is the point - a different principal in one of them would make them genuinely different and the comparison meaningless (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-z0-9.-]+\\.amazonaws\\.com$", var.trusted_service))
    error_message = "trusted_service must be an AWS service principal such as ec2.amazonaws.com."
  }
}
variable "policy_actions" {
  type        = list(string)
  default     = ["s3:*", "s3-object-lambda:*"]
  description = "Actions the inline policy allows, as the _monolithic template had them. Wide on purpose - this project is about how a policy document is written, not about what it grants - and the same list feeds all three roles"

  validation {
    condition     = length(var.policy_actions) > 0
    error_message = "policy_actions must contain at least one action."
  }
  validation {
    condition     = alltrue([for action in var.policy_actions : can(regex("^[a-zA-Z0-9-]+:[a-zA-Z0-9*]+$", action))])
    error_message = "policy_actions must each look like a service:Action pair, e.g. s3:GetObject or s3:*."
  }
}
variable "policy_resources" {
  type        = list(string)
  default     = ["*"]
  description = "Resources the inline policy applies to, as the _monolithic template had them. A real policy would name buckets here; leaving it at \"*\" is what the original did and changing it would not change what the project demonstrates"

  validation {
    condition     = length(var.policy_resources) > 0
    error_message = "policy_resources must contain at least one resource."
  }
}
variable "policy_name" {
  type        = string
  default     = "GetS3Policy"
  description = "Name of the inline policy on each role, as the _monolithic template named it. The same name on all three is fine: an inline policy name is unique per role, not per account"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,128}$", var.policy_name))
    error_message = "policy_name must be 1-128 characters from the set IAM accepts for a policy name."
  }
}
