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

output "marker_file_path" {
  value       = local.outputs.marker_file_path.value
  description = "Where each stage drops its completion marker. Read back from the module rather than restated from the variable, so the until loops and the module cannot disagree about the path (rules.md B-5)"
}

output "timestamps_command" {
  value       = local.outputs.timestamps_command.value
  description = "BEFORE_MARK and AFTER_MARK are written by user data 120 seconds apart; COMMAND1 through COMMAND3 by the three associations. Every timestamp later than the one before it is the demonstration - the marker file is what makes each stage observe that the previous one finished, which depends_on alone does not"
}

output "markers_command" {
  value       = local.outputs.markers_command.value
  description = "One file per completed stage, in the order they were created. AFTER_MARK later than the userdata marker would mean the marker was touched too early, which is the failure this pattern is written to avoid (rules.md B-4)"
}

output "association_status_command" {
  value       = local.outputs.association_status_command.value
  description = "Success for every association. This is the view that does not tell you whether the remote command finished, which is why the markers exist - an association can report success on a command that was still running work in the background"
}
