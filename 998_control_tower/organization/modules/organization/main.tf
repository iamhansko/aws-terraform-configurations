# Created only when the caller did not supply an existing root, so this module
# works both for a greenfield organization and for an account that already has
# one (rules.md B-4).
resource "aws_organizations_organization" "organization" {
  count       = var.organization_root_id == null ? 1 : 0
  feature_set = var.feature_set

  # aws_service_access_principals and enabled_policy_types are deliberately not
  # configured. Control Tower turns on trusted access for its own dependencies
  # (controltower, config, cloudtrail, sso, ...) and enables SERVICE_CONTROL_POLICY
  # while it builds the landing zone. Declaring either attribute here would make
  # every later plan propose stripping whatever Control Tower added, so the
  # attributes are left to it and ignored.
  lifecycle {
    ignore_changes = [aws_service_access_principals, enabled_policy_types]
  }
}
locals {
  # Single place the root ID is resolved, whether it came from the caller or from
  # the organization created above.
  root_id = var.organization_root_id != null ? var.organization_root_id : aws_organizations_organization.organization[0].roots[0].id
}
resource "aws_organizations_organizational_unit" "organizational_unit" {
  for_each = toset(var.organizational_unit_names)

  name      = each.value
  parent_id = local.root_id
  tags      = var.organizational_unit_tags
}
