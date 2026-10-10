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
  description = "The cluster both services run in. Its default Service Connect namespace is the one both join"
}
output "service_connect_client_alias" {
  value       = local.outputs.service_connect_client_alias.value
  description = "host:port the nginx service is published at. It resolves only inside tasks that run a Service Connect proxy in this namespace - not on the workbench and not in DNS"
}
output "namespace_services_command" {
  value       = local.outputs.namespace_services_command.value
  description = "One Cloud Map service per Service Connect endpoint, created by ECS with the nginx service"
}
output "namespace_instances_command" {
  value       = local.outputs.namespace_instances_command.value
  description = "The tasks ECS registered under the endpoint, one per running nginx task. The client side proxy balances across these"
}
output "service_connect_test_commands" {
  value       = local.outputs.service_connect_test_commands.value
  description = "The _monolithic template output ServiceConnectTestCommands, as one line. The template printed it with a newline before every option and no line continuation, so a pasted copy ran a bare aws ecs execute-command and then tried each option as a command of its own. In the shell, curl the endpoint above"
}
output "service_connect_curl_command" {
  value       = local.outputs.service_connect_curl_command.value
  description = "The test in one command: the nginx welcome page, fetched by name from inside the client task through its proxy"
}
output "service_connect_hosts_command" {
  value       = local.outputs.service_connect_hosts_command.value
  description = "Service Connect does not use DNS for the alias. ECS wrote it into the task's /etc/hosts when the task started, pointing at the local proxy - which is why dig and nslookup cannot find it while curl can, and why a client task started before the endpoint existed never sees it"
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
