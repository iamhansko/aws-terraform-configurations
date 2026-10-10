# Every value here is a projection of local.outputs in main.tf, which the README written onto the workbench
# renders from the same map - so no value expression exists twice, and an output cannot be added without also
# appearing in that README (rules.md B-5/H-2).
#
# description is the one thing that cannot be projected: Terraform rejects an expression in an output's
# description ("Variables not allowed"), so the wording is a literal on both sides.
output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "The workbench, as the _monolithic template output VsCode. Every command below runs from its terminal, where the AWS CLI is set to this region and has the Session Manager plugin that execute-command needs"
}
output "cluster_name" {
  value       = local.outputs.cluster_name.value
  description = "The cluster the aws-cli service runs in"
}
output "execute_command_agent_command" {
  value       = local.outputs.execute_command_agent_command.value
  description = "enableExecuteCommand True and the ExecuteCommandAgent RUNNING. An empty table means no task is running yet - the service events below say why"
}
output "ecs_exec_command" {
  value       = local.outputs.ecs_exec_command.value
  description = "The _monolithic template output EcsExecCommand, as one line. The template printed it with a newline before every option and no line continuation, so a pasted copy ran a bare aws ecs execute-command and then tried each option as a command of its own"
}
output "ecs_exec_identity_command" {
  value       = local.outputs.ecs_exec_identity_command.value
  description = "execute-command runs a single command too. This one shows that a session runs as the task role - an assumed-role ARN, with no credentials configured in the container - which is also what decides what the session can do in the account"
}
output "container_log_command" {
  value       = local.outputs.container_log_command.value
  description = "The container output, and the ECS Exec sessions: under the default session logging ECS writes each session to the task log group, provided the image carries the script and cat utilities the upload uses. A session that works but never appears here is an image without them"
}
output "service_events_command" {
  value       = local.outputs.service_events_command.value
  description = "Nearly every failure is reported here first, not in Terraform"
}
output "container_instance_status_command" {
  value       = local.outputs.container_instance_status_command.value
  description = "Which instances registered with the cluster. Instances launched but missing here cannot reach the ECS endpoint or lack the container instance role policy"
}
output "scaling_activities_command" {
  value       = local.outputs.scaling_activities_command.value
  description = "Launch failures are recorded here rather than in ECS"
}
output "private_key_command" {
  value       = local.outputs.private_key_command.value
  description = "Retrieves the generated private key from Parameter Store. No security group opens port 22; this is for the case where the SSM agent is what is broken"
}
