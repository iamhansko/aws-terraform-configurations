# Every value here is a projection of local.outputs in main.tf, which the README written onto the workbench
# renders from the same map - so no value expression exists twice, and an output cannot be added without also
# appearing in that README (rules.md B-5/H-2).
#
# description is the one thing that cannot be projected: Terraform rejects an expression in an output's
# description ("Variables not allowed"), so the wording is a literal on both sides.
output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "The IDE, through CloudFront. The instance accepts port 8000 only from CloudFront's prefix list, so this is the only way in"
}
output "security_note" {
  value       = local.outputs.security_note.value
  description = "What an unauthenticated IDE session can do here: AdministratorAccess, cluster-admin, and an MCP server with write and Secret access"
}
output "cluster_name" {
  value       = local.outputs.cluster_name.value
  description = "The cluster Q inspects through the EKS MCP server"
}
output "mcp_servers" {
  value       = local.outputs.mcp_servers.value
  description = "The MCP servers written into Q's configuration"
}
output "mcp_config_command" {
  value       = local.outputs.mcp_config_command.value
  description = "1. The MCP configuration file as it landed on the instance"
}
output "q_login_command" {
  value       = local.outputs.q_login_command.value
  description = "2. Signs in to Q. Interactive, so Terraform cannot do it"
}
output "q_chat_command" {
  value       = local.outputs.q_chat_command.value
  description = "3. Asks Q about the live cluster, which is the demo"
}
output "q_mcp_status_command" {
  value       = local.outputs.q_mcp_status_command.value
  description = "4. Which MCP servers Q actually started"
}
output "cluster_check_command" {
  value       = local.outputs.cluster_check_command.value
  description = "5. The same question without Q, for telling the two failure modes apart"
}
output "cloudfront_status_command" {
  value       = local.outputs.cloudfront_status_command.value
  description = "6. Whether the distribution has finished deploying"
}
output "prefix_list_command" {
  value       = local.outputs.prefix_list_command.value
  description = "7. The CloudFront prefix list the instance trusts, looked up by name rather than hardcoded per region"
}
output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "Re-points kubectl at the cluster, with the --region the original omitted"
}
output "private_key_command" {
  value       = local.outputs.private_key_command.value
  description = "Reads the workbench's SSH private key out of SSM Parameter Store"
}
