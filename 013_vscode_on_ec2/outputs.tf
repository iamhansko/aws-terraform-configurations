# Every output is a projection of local.outputs in main.tf, which is also what
# the README on the instance is rendered from (rules.md H-2). No value
# expression is written here: an output that built its own value would be
# missing from that README, and nothing would fail to tell anyone.
#
# description is the one thing repeated, because Terraform rejects an expression
# there ("Variables not allowed") - it has to be a literal.
output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "URL to access the code-server web UI. code-server runs with authentication disabled, so treat this URL as the credential"
}
output "instance_id" {
  value       = local.outputs.instance_id.value
  description = "ID of the VS Code EC2 instance"
}
output "private_key_parameter" {
  value       = local.outputs.private_key_parameter.value
  description = "Name of the SSM parameter holding the generated SSH private key. The parameter is a SecureString, so only its name is exposed here rather than the key itself"
}
output "session_manager_command" {
  value       = local.outputs.session_manager_command.value
  description = "Command opening a shell on the instance through SSM Session Manager, with no inbound port required"
}
output "port_forward_command" {
  value       = local.outputs.port_forward_command.value
  description = "Command forwarding the code-server port to localhost through SSM, the safe alternative to opening the port to the internet"
}
output "docker_check_command" {
  value       = local.outputs.docker_check_command.value
  description = "Command verifying Docker is usable from a code-server terminal without sudo"
}
output "bootstrap_log_command" {
  value       = local.outputs.bootstrap_log_command.value
  description = "Command tailing the user data log, where every bootstrap step is traced"
}
