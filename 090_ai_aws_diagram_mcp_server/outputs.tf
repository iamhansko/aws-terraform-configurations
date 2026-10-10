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
  description = "Worth reading before using it. code-server runs with auth: none and CloudFront adds no authentication of its own, so anyone with the URL has the IDE - and the instance holds AdministratorAccess. Both MCP servers configured here only read, but Q can also run shell commands with the same credentials. That is the demo working as intended; it is also why this should not be left running"
}
output "mcp_servers" {
  value       = local.outputs.mcp_servers.value
  description = "What Q can reach. Built from a typed object rather than the escaped JSON the original embedded in an SSM parameter, which closed one more brace than it opened"
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
  description = "The demo. Q writes Python for the diagrams package and the diagram server renders it with GraphViz. Started from a directory of its own, so the generated-diagrams folder it writes lands somewhere code-server shows"
}
output "q_mcp_status_command" {
  value       = local.outputs.q_mcp_status_command.value
  description = "A server whose uvx package failed to download is reported here rather than in the config. The first thing to check when Q answers without calling a tool"
}
output "diagrams_command" {
  value       = local.outputs.diagrams_command.value
  description = "The diagram server writes PNGs into a generated-diagrams directory under the workspace Q passes it, or under the system temporary directory when Q passes none"
}
output "graphviz_command" {
  value       = local.outputs.graphviz_command.value
  description = "The diagram server renders with dot. The _monolithic template never installed it, so the server started and every diagram request failed"
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
output "private_key_command" {
  value       = local.outputs.private_key_command.value
  description = "Retrieves the generated private key from Parameter Store, where CloudFormation puts a generated key pair. No security group opens port 22; this is for the case where the SSM agent is what is broken"
}
