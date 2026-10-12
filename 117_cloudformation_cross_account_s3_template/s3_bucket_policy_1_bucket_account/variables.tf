variable "aws_region" {
  type        = string
  default     = null
  description = "Region the bucket is created in. Null follows the provider chain. The template URL this root outputs carries the region, so the stack account does not have to match it"

  validation {
    condition     = var.aws_region == null || can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a region code such as ap-northeast-2, or null to follow the provider chain."
  }
}
variable "bucket_account_id" {
  type        = string
  description = "The account this root must be applied to. Checked against the running credentials, which is the only thing that stops this bucket being created in the stack account by mistake (rules.md I-2)"

  validation {
    condition     = can(regex("^[0-9]{12}$", var.bucket_account_id))
    error_message = "bucket_account_id must be a 12-digit AWS account ID."
  }
}
variable "stack_account_id" {
  type        = string
  description = "The account that creates the CloudFormation stack from this bucket's template, and is granted read on it. The _monolithic template called this cloud_formation_account_id"

  validation {
    condition     = can(regex("^[0-9]{12}$", var.stack_account_id))
    error_message = "stack_account_id must be a 12-digit AWS account ID."
  }
  validation {
    # A pair constraint, so cross-variable (rules.md B-1). In one account the bucket policy grants nothing the
    # account did not already have, and the demo shows nothing.
    condition     = var.stack_account_id != var.bucket_account_id
    error_message = "stack_account_id must differ from bucket_account_id - the point of this pair of roots is the cross-account read. To try the template in one account, use the s3_presigned_url root instead."
  }
}
variable "template_path" {
  type        = string
  default     = "templates/vpc.yaml"
  description = "Path to the CloudFormation template to upload, relative to this root"

  validation {
    condition     = can(regex("\\.(ya?ml|json)$", var.template_path))
    error_message = "template_path must point at a .yaml, .yml or .json file."
  }
}
variable "template_key" {
  type        = string
  default     = "template.yaml"
  description = "Object key the template is stored under, as the _monolithic template had it"

  validation {
    condition     = length(var.template_key) > 0 && !startswith(var.template_key, "/")
    error_message = "template_key must not be empty and must not start with a slash."
  }
}
