output "root_id" {
  value       = local.root_id
  description = "Root ID of the organization, whether it was supplied by the caller or created here"
}
output "organization_id" {
  value       = var.organization_root_id == null ? aws_organizations_organization.organization[0].id : null
  description = "ID of the organization created by this module, or null when an existing root was supplied"
}
output "organization_arn" {
  value       = var.organization_root_id == null ? aws_organizations_organization.organization[0].arn : null
  description = "ARN of the organization created by this module, or null when an existing root was supplied"
}
output "master_account_id" {
  value       = var.organization_root_id == null ? aws_organizations_organization.organization[0].master_account_id : null
  description = "Account ID of the management account, or null when an existing root was supplied. This is the account the landing zone is launched from"
}
output "organizational_unit_ids" {
  value       = { for name, ou in aws_organizations_organizational_unit.organizational_unit : name => ou.id }
  description = "OU name to OU ID, so callers select an OU by the name they asked for rather than by index"
}
output "organizational_unit_arns" {
  value       = { for name, ou in aws_organizations_organizational_unit.organizational_unit : name => ou.arn }
  description = "OU name to OU ARN. aws_controltower_control targets an OU by ARN, so this is what a control module consumes"
}
output "organizational_unit_names" {
  value       = var.organizational_unit_names
  description = "Names of the OUs created, re-exposed so a caller picking a target OU references one source of truth (rules.md B-5)"
}
