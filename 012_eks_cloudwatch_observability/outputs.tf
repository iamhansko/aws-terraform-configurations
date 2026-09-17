# Every output is a projection of local.outputs in main.tf, which is also what
# the README on the instance is rendered from (rules.md H-2). No value
# expression is written here: an output that built its own value would be
# missing from that README, and nothing would fail to tell anyone.
#
# description is the one thing repeated, because Terraform rejects an expression
# there ("Variables not allowed") - it has to be a literal.
output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "URL to access the code-server web UI on the VS Code EC2 instance"
}
output "cluster_name" {
  value       = local.outputs.cluster_name.value
  description = "Name of the EKS cluster, and the middle segment of every log group Fluent Bit writes to"
}
output "cluster_endpoint" {
  value       = local.outputs.cluster_endpoint.value
  description = "API server endpoint of the EKS cluster"
}
output "cloudwatch_agent_role_arn" {
  value       = local.outputs.cloudwatch_agent_role_arn.value
  description = "ARN of the IAM role the CloudWatch agent assumes through EKS Pod Identity"
}
output "container_log_components" {
  value       = local.outputs.container_log_components.value
  description = "Comma-separated component names Fluent Bit was given a dedicated log pipeline for"
}
output "log_group_names" {
  value       = local.outputs.log_group_names.value
  description = "Newline-separated CloudWatch Logs group each component's pipeline writes to"
}
output "fluent_bit_pods_command" {
  value       = local.outputs.fluent_bit_pods_command.value
  description = "Command listing the CloudWatch agent and Fluent Bit pods, one per node"
}
output "fluent_bit_config_command" {
  value       = local.outputs.fluent_bit_config_command.value
  description = "Command dumping the Fluent Bit ConfigMap, to confirm the addon applied the rendered pipelines"
}
output "log_insights_url" {
  value       = local.outputs.log_insights_url.value
  description = "CloudWatch Logs Insights console URL where the queries below are run"
}
output "log_insights_query_by_node" {
  value       = local.outputs.log_insights_query_by_node.value
  description = "Logs Insights query filtering one node's logs, with a placeholder node name to replace"
}
output "log_insights_query_by_container" {
  value       = local.outputs.log_insights_query_by_container.value
  description = "Logs Insights query filtering one container's logs"
}
