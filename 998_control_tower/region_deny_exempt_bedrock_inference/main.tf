data "aws_region" "current" {}
locals {
  # Defaults to governing only the Region this provider points at, matching the
  # _monolithic template. Resolved once here so the landing zone and the Region
  # deny control below cannot end up with different lists.
  governed_regions = coalesce(var.governed_regions, [data.aws_region.current.region])

  # The control's allow list defaults to exactly what the landing zone governs.
  allowed_regions = coalesce(var.allowed_regions, local.governed_regions)
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
# The variant's reason for existing: deny every Region outside the governed set
# for this OU, while letting Bedrock through. Bedrock cross-Region inference
# profiles dispatch requests to Regions the landing zone does not govern, so
# without the exemption every inference call is denied by the control.
module "region_deny_control" {
  source = "./modules/control_tower_control"

  control_identifier = var.region_deny_control_identifier
  # Selected out of the organization module's name-to-ARN map, so the target
  # follows the OU that was actually created rather than a hand-copied ARN
  # (rules.md #5).
  target_identifier = module.organization.organizational_unit_arns[var.control_target_ou_name]

  # Values are JSON documents rather than plain strings, which is what the
  # Control Tower API expects for these two parameters.
  parameters = {
    AllowedRegions  = jsonencode(local.allowed_regions)
    ExemptedActions = jsonencode(var.exempted_actions)
  }

  # A control can only be enabled once Control Tower governs the target OU, which
  # cannot be true before the landing zone exists. target_identifier only orders
  # this module after the OU, so the landing zone dependency is explicit
  # (rules.md #22). It also makes terraform destroy disable the control before
  # tearing the landing zone down, rather than leaving an EnabledControl pointing
  # at a landing zone that is going away.
  depends_on = [module.organization, module.control_tower_landing_zone]
}
