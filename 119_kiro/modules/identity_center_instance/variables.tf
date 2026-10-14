variable "existing_instance_arn" {
  type        = string
  default     = null
  description = "ARN of an IAM Identity Center instance that already exists in the provider region, or null to create one"

  validation {
    condition     = var.existing_instance_arn == null || can(regex("^arn:aws[a-zA-Z-]*:sso:::instance/(sso)?ins-[a-zA-Z0-9.-]{16}$", var.existing_instance_arn))
    error_message = "existing_instance_arn must be an IAM Identity Center instance ARN, or null."
  }

  validation {
    condition     = (var.existing_instance_arn == null) == (var.existing_identity_store_id == null)
    error_message = "existing_instance_arn and existing_identity_store_id must both be supplied for an existing instance, or both be null so this module creates one."
  }
}

variable "existing_identity_store_id" {
  type        = string
  default     = null
  description = "Identity Store ID paired with existing_instance_arn, or null to create an IAM Identity Center instance"

  validation {
    condition     = var.existing_identity_store_id == null || can(regex("^d-[0-9a-f]{10}$|^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.existing_identity_store_id))
    error_message = "existing_identity_store_id must be an Identity Store ID such as d-1234567890, or null."
  }
}
