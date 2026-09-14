variable "aws_region" {
  type        = string
  default     = null
  description = "Target AWS region, which becomes the landing zone's home Region. When null, falls back to the provider default chain (AWS_REGION, profile, etc.)"
}
variable "organization_root_id" {
  type        = string
  default     = null
  description = "Root ID of an AWS Organization that already exists. When null, the organization is created. The _monolithic template made this a required variable whose empty-string value meant \"create one\"; null is the idiomatic optional switch (rules.md #4)"

  validation {
    condition     = var.organization_root_id == null || can(regex("^r-[0-9a-z]{4,32}$", var.organization_root_id))
    error_message = "organization_root_id must be a valid Organizations root ID (e.g. r-abc1), or null to create a new organization."
  }
}
variable "organizational_unit_names" {
  type        = list(string)
  default     = ["Johan"]
  description = "Organizational units created under the root. The OU named by control_target_ou_name gets the Region deny control"

  validation {
    condition     = length(var.organizational_unit_names) > 0
    error_message = "organizational_unit_names must contain at least one OU name."
  }
}
variable "control_target_ou_name" {
  type        = string
  default     = "Johan"
  description = "Which OU from organizational_unit_names the Region deny control is enabled on. Selected by name rather than by list index so reordering the list cannot silently retarget the control"

  validation {
    condition     = length(var.control_target_ou_name) > 0
    error_message = "control_target_ou_name must not be empty."
  }
}
variable "audit_account_id" {
  type        = string
  description = "Account ID of the Audit account, used for both the cross-account security roles and the Config aggregator. Must already exist: Control Tower does not create it as part of a landing zone launched through this API"

  validation {
    condition     = can(regex("^[0-9]{12}$", var.audit_account_id))
    error_message = "audit_account_id must be a 12-digit AWS account ID."
  }
}
variable "log_archive_account_id" {
  type        = string
  description = "Account ID of the Log Archive account, which receives centralized CloudTrail and Config logs. Must already exist"

  validation {
    condition     = can(regex("^[0-9]{12}$", var.log_archive_account_id))
    error_message = "log_archive_account_id must be a 12-digit AWS account ID."
  }
}
variable "landing_zone_version" {
  type        = string
  default     = "4.0"
  description = "Landing zone version. Quoted on purpose: the _monolithic template declared this as a string with an unquoted 4.0 default, which HCL reads as the number 4 and converts to \"4\" - not a valid version"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+$", var.landing_zone_version))
    error_message = "landing_zone_version must be a major.minor string such as \"4.0\"."
  }
}
variable "governed_regions" {
  type        = list(string)
  default     = null
  description = "Regions the landing zone governs. When null, only the provider's Region is governed, matching the _monolithic behaviour. Must include the management account's own Region"

  validation {
    condition     = var.governed_regions == null || length(coalesce(var.governed_regions, [])) > 0
    error_message = "governed_regions must contain at least one Region, or be null to default to the provider's Region."
  }
}
variable "logging_bucket_retention_days" {
  type        = number
  default     = 365
  description = "Retention for the centralized logging and Config logging buckets"

  validation {
    condition     = var.logging_bucket_retention_days >= 1
    error_message = "logging_bucket_retention_days must be at least 1."
  }
}
variable "access_logging_bucket_retention_days" {
  type        = number
  default     = 3650
  description = "Retention for the access logging buckets that record reads of the logging buckets"

  validation {
    condition     = var.access_logging_bucket_retention_days >= 1
    error_message = "access_logging_bucket_retention_days must be at least 1."
  }
}
variable "backup_enabled" {
  type        = bool
  default     = false
  description = "Whether Control Tower sets up centralized AWS Backup. Enabling it also requires backup_admin_account_id, backup_central_account_id and backup_kms_key_arn"
}
variable "backup_admin_account_id" {
  type        = string
  default     = null
  description = "Account ID hosting AWS Backup Audit Manager, required when backup_enabled is true"

  validation {
    condition     = var.backup_admin_account_id == null || can(regex("^[0-9]{12}$", var.backup_admin_account_id))
    error_message = "backup_admin_account_id must be a 12-digit AWS account ID, or null."
  }
}
variable "backup_central_account_id" {
  type        = string
  default     = null
  description = "Account ID hosting the central AWS Backup vault, required when backup_enabled is true"

  validation {
    condition     = var.backup_central_account_id == null || can(regex("^[0-9]{12}$", var.backup_central_account_id))
    error_message = "backup_central_account_id must be a 12-digit AWS account ID, or null."
  }
}
variable "backup_kms_key_arn" {
  type        = string
  default     = null
  description = "KMS key encrypting the central backup vault, required when backup_enabled is true"

  validation {
    condition     = var.backup_kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:", var.backup_kms_key_arn))
    error_message = "backup_kms_key_arn must be a valid KMS key ARN, or null."
  }
}
variable "landing_zone_tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to the landing zone. The _monolithic template carried a placeholder { x = \"y\" }, dropped here"

  validation {
    condition     = alltrue([for key in keys(var.landing_zone_tags) : length(key) > 0])
    error_message = "landing_zone_tags must not contain empty tag keys."
  }
}
variable "region_deny_control_identifier" {
  type        = string
  default     = "arn:aws:controlcatalog:::control/ka8e3pkqefnjsxuyc26ji580"
  description = "Control Catalog ARN of the OU-level Region deny control (CT.MULTISERVICE.PV.1). This is the OU-scoped control that takes AllowedRegions and ExemptedActions, as distinct from AWS-GR_REGION_DENY, which applies to the whole landing zone and is configured through landing zone settings rather than as an enabled control"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:(controlcatalog|controltower):", var.region_deny_control_identifier))
    error_message = "region_deny_control_identifier must be a controlcatalog or controltower control ARN."
  }
}
variable "allowed_regions" {
  type        = list(string)
  default     = null
  description = "Regions exempted from the Region deny control. When null, the governed Regions are used, which keeps the control's allow list from drifting away from what the landing zone actually governs"

  validation {
    condition     = var.allowed_regions == null || length(coalesce(var.allowed_regions, [])) > 0
    error_message = "allowed_regions must contain at least one Region, or be null to reuse the governed Regions."
  }
}
variable "exempted_actions" {
  type        = list(string)
  default     = ["bedrock:*"]
  description = "IAM action patterns allowed to run outside the allowed Regions. The point of this variant: Bedrock cross-Region inference profiles route requests to Regions outside the governed set, so bedrock:* has to be exempt or inference fails. The _monolithic template had \"besrock:*\", a typo that silently exempted nothing"

  validation {
    condition     = length(var.exempted_actions) > 0
    error_message = "exempted_actions must contain at least one action pattern."
  }

  validation {
    condition     = alltrue([for action in var.exempted_actions : can(regex("^[a-z0-9-]+:[A-Za-z0-9*]+$", action))])
    error_message = "exempted_actions entries must look like <service>:<action> with the service lowercase (e.g. bedrock:* or bedrock:InvokeModel). A typo in the service prefix exempts nothing and fails silently."
  }
}
