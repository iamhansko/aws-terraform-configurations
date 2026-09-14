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
  description = "OU name to OU ARN for every organizational unit created. Enabling a control on one of these is what the region_deny_exempt_bedrock_inference variant adds"
}
output "governed_regions" {
  value       = module.control_tower_landing_zone.governed_regions
  description = "Regions the landing zone governs"
}
