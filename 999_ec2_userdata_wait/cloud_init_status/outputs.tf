# Every value here is a projection of local.outputs in main.tf, which the README written onto the
# workbench renders from the same map - so no value expression exists twice (rules.md B-5/H-2).
#
# The descriptions are the one thing that cannot be projected: Terraform does not allow an expression
# in an output description ("Variables not allowed"), so the wording is repeated here as a literal
# while the values are not.

output "vscode" {
  value       = local.outputs.vscode.value
  description = "Open the IDE here. The timestamp files this project writes are in the home directory the IDE opens, which is the whole point - the demonstration is what order they carry"
}

output "instance_id" {
  value       = local.outputs.instance_id.value
  description = "The instance every SSM Association here targets"
}

output "timestamps_command" {
  value       = local.outputs.timestamps_command.value
  description = "COMMAND0.md is written by user data, COMMAND1.md by the association. COMMAND1 later than COMMAND0 is the thing being demonstrated: `cloud-init status --wait` made the association observe that user data had finished"
}

output "cloud_init_status_command" {
  value       = local.outputs.cloud_init_status_command.value
  description = "`cloud-init status --wait` blocks until cloud-init reports done, which is the alternative this variant shows. It needs no marker file - and that is why this root has no until loop, unlike the marker_files variant (rules.md D-5)"
}

output "cloud_init_log_command" {
  value       = local.outputs.cloud_init_log_command.value
  description = "The timestamp cloud-init recorded for the final stage. Comparing it against COMMAND1.md shows how much of the wait was real rather than the sleep"
}
