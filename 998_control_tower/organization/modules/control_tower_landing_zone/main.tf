# The manifest is assembled from variables instead of being a hardcoded JSON
# blob, so retention, governed Regions and the shared account IDs are inputs
# rather than edits to a literal (rules.md #7).
#
# Shape follows the published landing zone 4.0 schema
# (https://docs.aws.amazon.com/controltower/latest/userguide/landing-zone-schemas.html):
# the top level allows exactly accessManagement, backup, centralizedLogging,
# governedRegions, securityRoles and config, with additionalProperties: false -
# so nothing else may be added. Note organizationStructure belongs to the 3.1
# through 3.3 schemas only and would be rejected at 4.0.
#
# Each of securityRoles, centralizedLogging, config and backup requires
# "enabled", and requires its accountId (or, for backup, its configurations)
# only when enabled is true. The merge()/conditional pattern below emits those
# keys only when they carry a value: a bare conditional returning objects with
# different attributes would fail Terraform's type unification, whereas merging
# an empty object is well defined.
locals {
  security_roles = merge(
    { enabled = var.security_roles_enabled },
    var.security_roles_enabled ? { accountId = var.security_roles_account_id } : {},
  )

  centralized_logging = merge(
    { enabled = var.centralized_logging_enabled },
    var.centralized_logging_enabled ? {
      accountId = var.centralized_logging_account_id
      configurations = merge(
        {
          loggingBucket       = { retentionDays = var.logging_bucket_retention_days }
          accessLoggingBucket = { retentionDays = var.access_logging_bucket_retention_days }
        },
        var.logging_kms_key_arn == null ? {} : { kmsKeyArn = var.logging_kms_key_arn },
      )
    } : {},
  )

  config = merge(
    { enabled = var.config_enabled },
    var.config_enabled ? {
      accountId = var.config_account_id
      configurations = merge(
        {
          loggingBucket       = { retentionDays = var.config_logging_bucket_retention_days }
          accessLoggingBucket = { retentionDays = var.config_access_logging_bucket_retention_days }
        },
        var.config_kms_key_arn == null ? {} : { kmsKeyArn = var.config_kms_key_arn },
      )
    } : {},
  )

  # When backup is enabled the schema requires all three of backupAdmin,
  # centralBackup and kmsKeyArn, which the precondition below enforces.
  backup = merge(
    { enabled = var.backup_enabled },
    var.backup_enabled ? {
      configurations = {
        backupAdmin   = { accountId = var.backup_admin_account_id }
        centralBackup = { accountId = var.backup_central_account_id }
        kmsKeyArn     = var.backup_kms_key_arn
      }
    } : {},
  )

  manifest = {
    accessManagement   = { enabled = var.access_management_enabled }
    governedRegions    = var.governed_regions
    securityRoles      = local.security_roles
    centralizedLogging = local.centralized_logging
    config             = local.config
    backup             = local.backup
  }
}
resource "aws_controltower_landing_zone" "control_tower_landing_zone" {
  manifest_json     = jsonencode(local.manifest)
  version           = var.landing_zone_version
  remediation_types = var.remediation_types
  tags              = var.tags

  lifecycle {
    # The schema expresses these as if/then rules, which Terraform's variable
    # validation cannot express because they span several variables. Catching
    # them at plan time is worth it: a malformed manifest otherwise surfaces as
    # a ValidationException after Control Tower has already begun a setup that
    # takes upwards of an hour.
    precondition {
      condition     = !var.security_roles_enabled || var.security_roles_account_id != null
      error_message = "security_roles_account_id is required when security_roles_enabled is true (schema: SecurityRoles requires accountId when enabled)."
    }
    precondition {
      condition     = !var.centralized_logging_enabled || var.centralized_logging_account_id != null
      error_message = "centralized_logging_account_id is required when centralized_logging_enabled is true (schema: CentralizedLogging requires accountId when enabled)."
    }
    precondition {
      condition     = !var.config_enabled || var.config_account_id != null
      error_message = "config_account_id is required when config_enabled is true (schema: Config requires accountId when enabled)."
    }
    precondition {
      condition     = !var.backup_enabled || (var.backup_admin_account_id != null && var.backup_central_account_id != null && var.backup_kms_key_arn != null)
      error_message = "backup_admin_account_id, backup_central_account_id and backup_kms_key_arn are all required when backup_enabled is true (schema: Backup requires configurations.backupAdmin, configurations.centralBackup and configurations.kmsKeyArn when enabled)."
    }
  }
}
