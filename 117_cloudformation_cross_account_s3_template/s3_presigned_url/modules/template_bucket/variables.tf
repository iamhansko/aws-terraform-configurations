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
  description = "Whether terraform destroy empties the bucket first, which covers copies uploaded by hand from the workbench"
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
    error_message = "template_body must contain a Resources section - CloudFormation rejects one without, but only once someone tries to create a stack from the URL."
  }
}
