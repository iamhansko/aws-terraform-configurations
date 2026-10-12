variable "aws_region" {
  type        = string
  default     = null
  description = "Region the role is created in and the stack command targets. Null follows the provider chain"

  validation {
    condition     = var.aws_region == null || can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a region code such as ap-northeast-2, or null to follow the provider chain."
  }
}
variable "stack_account_id" {
  type        = string
  description = "The account this root must be applied to - the same value the bucket account root was given as stack_account_id (rules.md I-2)"

  validation {
    condition     = can(regex("^[0-9]{12}$", var.stack_account_id))
    error_message = "stack_account_id must be a 12-digit AWS account ID."
  }
}
variable "template_url" {
  type        = string
  description = "The template_url output of ../s3_bucket_policy_1_bucket_account. Taken whole rather than rebuilt from a bucket name, which is what the _monolithic template did - with this account's region, so it named a different URL whenever the two roots ran in different regions"

  validation {
    condition     = can(regex("^https://[a-z0-9][a-z0-9.-]+\\.s3\\.[a-z0-9-]+\\.amazonaws\\.com/.+", var.template_url))
    error_message = "template_url must be a regional virtual-hosted S3 URL (https://<bucket>.s3.<region>.amazonaws.com/<key>) - copy the bucket account root's template_url output."
  }
}
variable "cloudformation_role_name" {
  type        = string
  default     = "CloudFormationIamRole"
  description = "Name of the CloudFormation service role, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,64}$", var.cloudformation_role_name))
    error_message = "cloudformation_role_name must be 1-64 characters from the set IAM accepts for a role name."
  }
}
variable "stack_name" {
  type        = string
  default     = "my-stack"
  description = "Name the create-stack command uses, as the _monolithic template's output had it. The stack is created by that command, not by Terraform"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{0,127}$", var.stack_name))
    error_message = "stack_name must start with a letter and be up to 128 characters of letters, digits and hyphens."
  }
}
