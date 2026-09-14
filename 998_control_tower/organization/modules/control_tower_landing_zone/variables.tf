variable "landing_zone_version" {
  type        = string
  default     = "4.0"
  description = "Landing zone version, and therefore which manifest schema applies. The manifest this module builds targets 4.0; 3.1 through 3.3 additionally require an organizationStructure block that 4.0 rejects, so changing this to a 3.x version needs the manifest changed too. Quoted deliberately: an unquoted 4.0 is an HCL number and converts to the string \"4\", which Control Tower rejects as a version"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+$", var.landing_zone_version))
    error_message = "landing_zone_version must be a major.minor string such as \"4.0\". An unquoted 4.0 in HCL becomes the number 4 and stringifies to \"4\", which is not a valid version."
  }
}
variable "governed_regions" {
  type        = list(string)
  description = "Regions the landing zone governs. Anything outside this list is denied by the mandatory Region deny policy, so the management account's own Region has to be included"

  validation {
    condition     = length(var.governed_regions) > 0
    error_message = "governed_regions must contain at least one Region."
  }

  validation {
    condition     = alltrue([for region in var.governed_regions : can(regex("^[a-z]{2}-[a-z-]*-[0-9]$", region))])
    error_message = "governed_regions entries must be Region codes matching the schema's pattern ^[a-z]{2}-[a-z-]*-[0-9]$ (e.g. ap-northeast-2)."
  }

  validation {
    condition     = length(distinct(var.governed_regions)) == length(var.governed_regions)
    error_message = "governed_regions must not contain duplicates."
  }
}
variable "access_management_enabled" {
  type        = bool
  default     = true
  description = "Whether Control Tower sets up IAM Identity Center for the landing zone. False means self-managing identity and access instead"
}
variable "security_roles_enabled" {
  type        = bool
  default     = true
  description = "Whether the Audit account's cross-account security roles are set up. Required for the Audit account to have read access across enrolled accounts"
}
variable "security_roles_account_id" {
  type        = string
  default     = null
  description = "Account ID that hosts the security roles, i.e. the Audit account. Required when security_roles_enabled is true"

  validation {
    condition     = var.security_roles_account_id == null || can(regex("^[0-9]{12}$", var.security_roles_account_id))
    error_message = "security_roles_account_id must be a 12-digit AWS account ID, or null."
  }
}
variable "centralized_logging_enabled" {
  type        = bool
  default     = true
  description = "Whether CloudTrail and Config logs from enrolled accounts are centralized into the Log Archive account"
}
variable "centralized_logging_account_id" {
  type        = string
  default     = null
  description = "Account ID that receives centralized logs, i.e. the Log Archive account. Required when centralized_logging_enabled is true"

  validation {
    condition     = var.centralized_logging_account_id == null || can(regex("^[0-9]{12}$", var.centralized_logging_account_id))
    error_message = "centralized_logging_account_id must be a 12-digit AWS account ID, or null."
  }
}
variable "logging_bucket_retention_days" {
  type        = number
  default     = 365
  description = "How long the centralized logging bucket keeps objects. The schema requires at least 1"

  validation {
    condition     = var.logging_bucket_retention_days >= 1
    error_message = "logging_bucket_retention_days must be at least 1 (schema: S3BucketConfiguration.retentionDays minimum 1)."
  }
}
variable "access_logging_bucket_retention_days" {
  type        = number
  default     = 3650
  description = "How long the access logging bucket keeps objects. Longer than the logging bucket by default, since access logs are the audit trail for reads of the logs themselves"

  validation {
    condition     = var.access_logging_bucket_retention_days >= 1
    error_message = "access_logging_bucket_retention_days must be at least 1 (schema: S3BucketConfiguration.retentionDays minimum 1)."
  }
}
variable "logging_kms_key_arn" {
  type        = string
  default     = null
  description = "Customer managed KMS key encrypting the centralized logging buckets. When null the key is omitted from the manifest and Control Tower uses its own default"

  validation {
    condition     = var.logging_kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:", var.logging_kms_key_arn))
    error_message = "logging_kms_key_arn must be a valid KMS key ARN, or null."
  }
}
variable "config_enabled" {
  type        = bool
  default     = true
  description = "Whether AWS Config is set up across governed accounts. Detective controls depend on it, so disabling this also disables them"
}
variable "config_account_id" {
  type        = string
  default     = null
  description = "Account ID that aggregates Config data, i.e. the Audit account. Required when config_enabled is true"

  validation {
    condition     = var.config_account_id == null || can(regex("^[0-9]{12}$", var.config_account_id))
    error_message = "config_account_id must be a 12-digit AWS account ID, or null."
  }
}
variable "config_logging_bucket_retention_days" {
  type        = number
  default     = 365
  description = "How long the Config logging bucket keeps objects"

  validation {
    condition     = var.config_logging_bucket_retention_days >= 1
    error_message = "config_logging_bucket_retention_days must be at least 1 (schema: S3BucketConfiguration.retentionDays minimum 1)."
  }
}
variable "config_access_logging_bucket_retention_days" {
  type        = number
  default     = 3650
  description = "How long the Config access logging bucket keeps objects"

  validation {
    condition     = var.config_access_logging_bucket_retention_days >= 1
    error_message = "config_access_logging_bucket_retention_days must be at least 1 (schema: S3BucketConfiguration.retentionDays minimum 1)."
  }
}
variable "config_kms_key_arn" {
  type        = string
  default     = null
  description = "Customer managed KMS key encrypting the Config buckets. When null the key is omitted from the manifest"

  validation {
    condition     = var.config_kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:", var.config_kms_key_arn))
    error_message = "config_kms_key_arn must be a valid KMS key ARN, or null."
  }
}
variable "backup_enabled" {
  type        = bool
  default     = false
  description = "Whether Control Tower sets up centralized AWS Backup. Enabling it makes backup_admin_account_id, backup_central_account_id and backup_kms_key_arn all mandatory, which the resource's preconditions enforce"
}
variable "backup_admin_account_id" {
  type        = string
  default     = null
  description = "Account ID hosting AWS Backup Audit Manager. Required when backup_enabled is true"

  validation {
    condition     = var.backup_admin_account_id == null || can(regex("^[0-9]{12}$", var.backup_admin_account_id))
    error_message = "backup_admin_account_id must be a 12-digit AWS account ID, or null."
  }
}
variable "backup_central_account_id" {
  type        = string
  default     = null
  description = "Account ID hosting the central AWS Backup vault. Required when backup_enabled is true"

  validation {
    condition     = var.backup_central_account_id == null || can(regex("^[0-9]{12}$", var.backup_central_account_id))
    error_message = "backup_central_account_id must be a 12-digit AWS account ID, or null."
  }
}
variable "backup_kms_key_arn" {
  type        = string
  default     = null
  description = "KMS key encrypting the central backup vault. Required when backup_enabled is true; the schema has no default for it"

  validation {
    condition     = var.backup_kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:", var.backup_kms_key_arn))
    error_message = "backup_kms_key_arn must be a valid KMS key ARN, or null."
  }
}
variable "remediation_types" {
  type        = list(string)
  default     = ["INHERITANCE_DRIFT"]
  description = "Drift types Control Tower remediates automatically. INHERITANCE_DRIFT is currently the only supported value, so this is effectively an on/off list"

  validation {
    condition     = alltrue([for remediation_type in var.remediation_types : contains(["INHERITANCE_DRIFT"], remediation_type)])
    error_message = "remediation_types may only contain INHERITANCE_DRIFT."
  }
}
variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to the landing zone. The _monolithic template carried a placeholder { x = \"y\" }, which is dropped here"

  validation {
    condition     = alltrue([for key in keys(var.tags) : length(key) > 0])
    error_message = "tags must not contain empty tag keys."
  }
}
