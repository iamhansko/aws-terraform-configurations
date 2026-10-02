# Every output is a projection of local.outputs in main.tf, which is also what the README
# written onto the VS Code instance is rendered from (rules.md H-2). No value expression is
# written here: an output that built its own value would be missing from that README, and
# nothing would fail to say so - the apply would succeed either way. Whether the pattern
# still holds is checked by counting: the number of output blocks here must equal the number
# of entries in local.outputs.
#
# The Datadog API key is deliberately absent. It is sensitive, and every entry in that map is
# written into a README served by a code-server with no authentication, so the key is
# reachable only through api_key_check_command (rules.md H-2).
#
# description is the one thing repeated, because Terraform rejects an expression there
# ("Variables not allowed") - it has to be a literal.
output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "URL to access the code-server web UI on the VS Code EC2 instance"
}
output "cluster_name" {
  value       = local.outputs.cluster_name.value
  description = "Name of the EKS cluster"
}
output "cluster_endpoint" {
  value       = local.outputs.cluster_endpoint.value
  description = "API server endpoint of the EKS cluster"
}
output "datadog_release" {
  value       = local.outputs.datadog_release.value
  description = "The Datadog operator release, its pinned chart version and the namespace it shares with the Secret and the DatadogAgent"
}
output "datadog_site" {
  value       = local.outputs.datadog_site.value
  description = "Datadog site the agent reports to, which must match the account's region"
}
output "agent_rollout_command" {
  value       = local.outputs.agent_rollout_command.value
  description = "Command confirming the agent DaemonSet rolled out on every node"
}
output "agent_status_command" {
  value       = local.outputs.agent_status_command.value
  description = "Command showing whether the operator accepted the DatadogAgent custom resource"
}
output "operator_logs_command" {
  value       = local.outputs.operator_logs_command.value
  description = "Command following the operator's log, where a rejected key or a misplaced Secret explains itself"
}
output "api_key_check_command" {
  value       = local.outputs.api_key_check_command.value
  description = "Command reading the API key back out of the cluster. A command rather than the value, because the README this is written into is served without authentication (rules.md H-2)"
}
output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "Command that points kubectl on the VS Code instance at the cluster"
}
