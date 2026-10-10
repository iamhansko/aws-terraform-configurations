output "completion_marker_name" {
  value       = local.completion_marker_name
  description = "Marker file the last build step writes. The next step in the root's chain waits for this name, which is derived here rather than restated there - adding an application with a higher order moves it, and a hard-coded name would then let the next step start before that application was built (rules.md B-5)"
}
output "completion_marker_file" {
  value       = "${var.marker_file_path}/${local.completion_marker_name}"
  description = "Absolute path of that marker, assembled here so the caller's until loop does not rejoin the directory and the name itself"
}
output "build_order" {
  value       = local.ordered_names
  description = "The applications in the order they are built, derived from their order fields. Worth reading in terraform output: this is the chain the marker files enforce, and it is not visible anywhere else"
}
output "build_root" {
  value       = var.build_root
  description = "Directory the build contexts are created under, handed back out so the caller can point a person at them (rules.md B-5)"
}
output "association_ids" {
  value       = { for name, key in local.build_keys : name => aws_ssm_association.image_build[key].association_id }
  description = "The association IDs by application name, for aws ssm describe-association-executions. Keyed by name rather than by the resource's own <name>-<tag> keys, so a caller does not have to know the tag to find a build; the IDs change with every source change, because each revision is a new association"
}
output "build_status_command" {
  value       = "for id in ${join(" ", [for association in aws_ssm_association.image_build : association.association_id])}; do aws ssm describe-association-executions --association-id $id --query 'AssociationExecutions[0].[AssociationId,Status,CreatedTime]' --output text; done"
  description = "Each build step's last execution status. Success for all of them is what says three images exist"
}
output "build_output_command" {
  value       = "aws ssm describe-association-executions --association-id ${aws_ssm_association.image_build[local.build_keys[local.ordered_names[0]]].association_id} --query 'AssociationExecutions[0].ExecutionId' --output text | xargs -r -I {} aws ssm describe-association-execution-targets --association-id ${aws_ssm_association.image_build[local.build_keys[local.ordered_names[0]]].association_id} --execution-id {} --query 'AssociationExecutionTargets[0].OutputSource.OutputSourceId' --output text | xargs -r -I {} aws ssm get-command-invocation --command-id {} --instance-id ${var.instance_id} --query '[Status,ExecutionElapsedTime,StandardOutputContent,StandardErrorContent]' --output json"
  description = "The first build step's actual command output, which is where a failure says what went wrong. An ExecutionElapsedTime of a fraction of a second means the script failed to parse rather than failed to run - which on a .tf file saved with CRLF line endings is what a broken heredoc delimiter looks like (rules.md A-4). Change the association id to read another step"
}
