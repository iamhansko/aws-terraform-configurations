output "landing_zone_arn" {
  value       = aws_controltower_landing_zone.control_tower_landing_zone.arn
  description = "ARN of the Control Tower landing zone"
}
output "landing_zone_identifier" {
  value       = aws_controltower_landing_zone.control_tower_landing_zone.id
  description = "Identifier of the Control Tower landing zone"
}
output "landing_zone_version" {
  value       = aws_controltower_landing_zone.control_tower_landing_zone.version
  description = "Version the landing zone is currently running"
}
output "latest_available_version" {
  value       = aws_controltower_landing_zone.control_tower_landing_zone.latest_available_version
  description = "Latest landing zone version AWS offers. Compare against landing_zone_version to see whether an upgrade is pending"
}
output "drift_status" {
  value       = aws_controltower_landing_zone.control_tower_landing_zone.drift_status
  description = "Drift status summary of the landing zone, which is what remediation_types acts on"
}
output "governed_regions" {
  value       = var.governed_regions
  description = "Regions the landing zone governs, re-exposed so a Region deny control's AllowedRegions parameter references one source of truth instead of restating the list (rules.md #5)"
}
output "manifest" {
  value       = local.manifest
  description = "Decoded manifest actually submitted, for inspecting what was sent without reading it back out of state as a JSON string"
}
