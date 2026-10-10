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
  description = "The cluster both services run in"
}
output "service_discovery_fqdn" {
  value       = local.outputs.service_discovery_fqdn.value
  description = "Name the nginx tasks resolve at. Any resolver in the VPC answers for it - it is a record in a private hosted zone - and nothing outside the VPC does"
}
output "service_discovery_instances_command" {
  value       = local.outputs.service_discovery_instances_command.value
  description = "One instance per running nginx task, with the task ENI address"
}
output "service_discovery_records_command" {
  value       = local.outputs.service_discovery_records_command.value
  description = "The A records in the namespace hosted zone, one per task - what a lookup from inside the VPC answers with"
}
output "service_discovery_test_commands" {
  value       = local.outputs.service_discovery_test_commands.value
  description = "The _monolithic template output ServiceDiscoveryTestCommands, as one line. The template printed it with a newline before every option and no line continuation, so a pasted copy ran a bare aws ecs execute-command and then tried each option as a command of its own. In the shell, dig and curl the name above"
}
output "service_discovery_dig_command" {
  value       = local.outputs.service_discovery_dig_command.value
  description = "The lookup in one command: one address per nginx task, from the VPC resolver, under the MULTIVALUE routing policy"
}
output "service_discovery_curl_command" {
  value       = local.outputs.service_discovery_curl_command.value
  description = "The nginx welcome page, fetched by name from inside the client task. The port comes from the client, not from DNS - an A record carries an address only"
}
output "app_service_events_command" {
  value       = local.outputs.app_service_events_command.value
  description = "Nearly every failure is reported here first, not in Terraform"
}
output "dnsutils_execute_command_agent_command" {
  value       = local.outputs.dnsutils_execute_command_agent_command.value
  description = "enableExecuteCommand True and the ExecuteCommandAgent RUNNING. An empty table means no dnsutils task is running"
}
output "container_instance_status_command" {
  value       = local.outputs.container_instance_status_command.value
  description = "Which instances registered with the cluster. Instances launched but missing here cannot reach the ECS endpoint or lack the container instance role policy"
}
output "private_key_command" {
  value       = local.outputs.private_key_command.value
  description = "Retrieves the generated private key from Parameter Store. No security group opens port 22; this is for the case where the SSM agent is what is broken"
}
