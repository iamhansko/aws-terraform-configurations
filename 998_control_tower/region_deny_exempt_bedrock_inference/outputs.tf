output "control_tower_landing_zone_arn" {
  value       = module.control_tower_landing_zone.landing_zone_arn
  description = "ControlTower LandingZone ARN"
}
output "control_tower_landing_zone_identifier" {
  value       = module.control_tower_landing_zone.landing_zone_identifier
  description = "ControlTower LandingZone ID"
}
output "landing_zone_drift_status" {
  value       = module.control_tower_landing_zone.drift_status
  description = "Drift status summary of the landing zone, which is what the INHERITANCE_DRIFT remediation type acts on"
}
output "landing_zone_upgrade_available" {
  value       = module.control_tower_landing_zone.latest_available_version != module.control_tower_landing_zone.landing_zone_version
  description = "Whether AWS offers a newer landing zone version than the one currently deployed"
}
output "landing_zone_manifest" {
  value       = module.control_tower_landing_zone.manifest
  description = "Decoded manifest submitted to Control Tower, for confirming what was sent without decoding a JSON string out of state"
}
output "organization_root_id" {
  value       = module.organization.root_id
  description = "Root ID of the organization, whether it already existed or was created here"
}
output "organizational_unit_arns" {
  value       = module.organization.organizational_unit_arns
  description = "OU name to OU ARN for every organizational unit created"
}
output "region_deny_control_arn" {
  value       = module.region_deny_control.control_arn
  description = "ARN of the EnabledControl resource for the Region deny control"
}
output "region_deny_control_parameters" {
  value       = module.region_deny_control.parameters
  description = "Effective Region deny parameters, decoded: which Regions are allowed and which actions are exempt from the restriction"
}
output "governed_regions" {
  value       = module.control_tower_landing_zone.governed_regions
  description = "Regions the landing zone governs"
}
