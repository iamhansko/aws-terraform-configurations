output "control_arn" {
  value       = aws_controltower_control.control_tower_control.arn
  description = "ARN of the EnabledControl resource Control Tower created"
}
output "control_identifier" {
  value       = var.control_identifier
  description = "ARN of the control that was enabled, re-exposed so callers reference one source of truth (rules.md #5)"
}
output "target_identifier" {
  value       = var.target_identifier
  description = "ARN of the OU the control was enabled on"
}
output "parameters" {
  value       = { for key, value in var.parameters : key => jsondecode(value) }
  description = "Parameters as applied, decoded back from JSON so the effective values are readable in terraform output"
}
