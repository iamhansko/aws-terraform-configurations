data "aws_region" "current" {}
locals {
  # Defaults to governing only the Region this provider points at, matching the
  # _monolithic template.
  governed_regions = coalesce(var.governed_regions, [data.aws_region.current.region])
}
module "organization" {
  source = "./modules/organization"

  organization_root_id      = var.organization_root_id
  organizational_unit_names = var.organizational_unit_names
}
module "control_tower_landing_zone" {
  source = "./modules/control_tower_landing_zone"

  landing_zone_version = var.landing_zone_version
  governed_regions     = local.governed_regions

  # The Audit account carries both the cross-account security roles and the
  # Config aggregator; the Log Archive account receives the centralized logs.
  security_roles_account_id      = var.audit_account_id
  config_account_id              = var.audit_account_id
  centralized_logging_account_id = var.log_archive_account_id

  logging_bucket_retention_days               = var.logging_bucket_retention_days
  access_logging_bucket_retention_days        = var.access_logging_bucket_retention_days
  config_logging_bucket_retention_days        = var.logging_bucket_retention_days
  config_access_logging_bucket_retention_days = var.access_logging_bucket_retention_days

  backup_enabled            = var.backup_enabled
  backup_admin_account_id   = var.backup_admin_account_id
  backup_central_account_id = var.backup_central_account_id
  backup_kms_key_arn        = var.backup_kms_key_arn

  tags = var.landing_zone_tags

  # A landing zone requires an organization with ALL features enabled, but the
  # manifest only carries account IDs - it references nothing the organization
  # module produces, so Terraform's graph would otherwise let the two be created
  # in parallel and the landing zone could reach the API first (rules.md #22).
  depends_on = [module.organization]
}
