# Every value here is a projection of local.outputs in main.tf, which the README written onto the workbench
# renders from the same map - so no value expression exists twice, and an output cannot be added without also
# appearing in that README (rules.md B-5/H-2).
#
# description is the one thing that cannot be projected: Terraform rejects an expression in an output's
# description ("Variables not allowed"), so the wording is a literal on both sides.
output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "Open the IDE here. The instance accepts its code-server port only from CloudFront's origin-facing prefix list, so this URL is the only way in"
}
output "security_note" {
  value       = local.outputs.security_note.value
  description = "Worth reading before using it. code-server runs with auth: none and CloudFront adds no authentication of its own, so anyone with the URL has the IDE. The instance holds AdministratorAccess, and the ECS MCP server runs with the write and sensitive-data switches shown here. Both are true by default, which lets Q build and push images, deploy and delete services, and read container logs and configuration. That is the demo working as intended; it is also why this should not be left running"
}
output "ecs_cluster_name" {
  value       = local.outputs.ecs_cluster_name.value
  description = "The cluster Q inspects and deploys into through the ECS MCP server"
}
output "capacity_providers" {
  value       = local.outputs.capacity_providers.value
  description = "The EC2 Auto Scaling capacity provider, which is the cluster default, and the Fargate providers attached alongside it, as the _monolithic template attached them"
}
output "mcp_servers" {
  value       = local.outputs.mcp_servers.value
  description = "What Q can reach. Built from a typed object rather than the escaped JSON the original embedded in an SSM parameter"
}
output "mcp_config_command" {
  value       = local.outputs.mcp_config_command.value
  description = "The file Q loads. If a server is missing from Q's tool list, compare this against the list above"
}
output "q_login_command" {
  value       = local.outputs.q_login_command.value
  description = "Run this in the IDE terminal. The CLI is installed but not authenticated - it needs a Builder ID or an IAM Identity Center sign-in, which is an interactive step Terraform cannot do"
}
output "q_chat_command" {
  value       = local.outputs.q_chat_command.value
  description = "The demo. Q calls the ECS MCP server, which uses the instance's credentials - so the answer comes from the live cluster rather than from the model's training data"
}
output "q_mcp_status_command" {
  value       = local.outputs.q_mcp_status_command.value
  description = "A server whose uvx package failed to download is reported here rather than in the config. The first thing to check when Q answers from training data instead of from the cluster"
}
output "ecs_mcp_server_log_command" {
  value       = local.outputs.ecs_mcp_server_log_command.value
  description = "Where the server records the AWS calls it made and why one failed. It writes nothing until Q has started it at least once"
}
output "container_instances_command" {
  value       = local.outputs.container_instances_command.value
  description = "Which instances registered and whether their agent is connected. Managed scaling moves the group to its minimum while nothing is running, so one instance on an idle cluster is expected"
}
output "capacity_provider_status_command" {
  value       = local.outputs.capacity_provider_status_command.value
  description = "The provider as ECS holds it, with its managed scaling settings"
}
output "scaling_activities_command" {
  value       = local.outputs.scaling_activities_command.value
  description = "Managed scaling shows up here as the group's desired count moving - which is why Terraform ignores changes to it - and a launch that failed shows up here rather than in ECS"
}
output "cluster_status_command" {
  value       = local.outputs.cluster_status_command.value
  description = "Registered instances and running versus pending task counts in one call"
}
output "q_cli_association_command" {
  value       = local.outputs.q_cli_association_command.value
  description = "When it failed, aws ssm describe-association-execution-targets with the execution ID shown here gives the command ID, and aws ssm get-command-invocation on that command ID shows the script output"
}
output "cloudfront_status_command" {
  value       = local.outputs.cloudfront_status_command.value
  description = "A 502 with the distribution Deployed means code-server did not answer - not started yet, or the instance was stopped and started and the origin still names its old public DNS name until the next apply"
}
output "prefix_list_command" {
  value       = local.outputs.prefix_list_command.value
  description = "The addresses CloudFront makes origin requests from, looked up by name rather than from the hardcoded per-region table the _monolithic template carried"
}
output "before_destroy_command" {
  value       = local.outputs.before_destroy_command.value
  description = "What Q deployed is not in Terraform state. ECS refuses to delete a cluster that still has active services, and the ECS MCP server creates ECR repositories through CloudFormation stacks of its own - list both, and remove what Q created, before destroying"
}
output "private_key_command" {
  value       = local.outputs.private_key_command.value
  description = "Retrieves the generated private key, shared by the workbench and the container instances, from Parameter Store, where CloudFormation puts a generated key pair. No security group opens port 22; this is for the case where the SSM agent is what is broken"
}
