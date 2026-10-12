variable "bucket_prefix" {
  type        = string
  default     = "cloudformation-templates-"
  description = "Prefix for the generated bucket name. cloudformation-templates- is what the _monolithic template used"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{0,36}$", var.bucket_prefix))
    error_message = "bucket_prefix must be 1-37 characters of lowercase letters, digits, periods and hyphens, starting with a letter or digit."
  }
}
variable "force_destroy" {
  type        = bool
  default     = true
  description = "Whether terraform destroy empties the bucket first. The template object is deleted by Terraform either way; this covers anything copied in by hand"
}
variable "reader_account_ids" {
  type        = list(string)
  description = "Accounts allowed to read the templates. Each is granted as its root principal, so a principal there still needs s3:GetObject in its own IAM policy"

  validation {
    condition     = length(var.reader_account_ids) > 0 && alltrue([for id in var.reader_account_ids : can(regex("^[0-9]{12}$", id))])
    error_message = "reader_account_ids must contain at least one 12-digit AWS account ID."
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
variable "template_body" {
  type        = string
  description = "The CloudFormation template to store"

  validation {
    condition     = can(regex("(?m)^Resources:", var.template_body))
    error_message = "template_body must contain a Resources section. S3 will store anything; CloudFormation rejects a template without one only when the stack account calls CreateStack."
  }
  validation {
    condition     = length(var.template_body) <= 1048576
    error_message = "template_body must be 1 MB or smaller, CloudFormation's limit for a template read from S3."
  }
}
