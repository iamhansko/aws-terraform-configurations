output "release_name" {
  value       = helm_release.datadog_operator.name
  description = "Name of the operator's Helm release"
}
output "chart_version" {
  value       = var.chart_version
  description = "Pinned chart version, re-exposed so what is installed is visible without reading the module (rules.md B-5)"
}
output "namespace" {
  value       = var.namespace
  description = "Namespace the operator, Secret and DatadogAgent share, re-exposed so callers do not restate it (rules.md B-5)"
}
output "agent_name" {
  value       = var.agent_name
  description = "Name of the DatadogAgent custom resource"
}
output "site" {
  value       = var.site
  description = "Datadog site the agent reports to. Worth surfacing: a key from an account in a different region authenticates at the TCP level and is then rejected, which reads as a bad key rather than a wrong site"
}
# No output exposes the API key. It is sensitive, and H-2 writes every output into a README
# on an instance whose code-server has no authentication in front of it, so a value here
# would be readable by anyone who can reach that instance (rules.md H-2). The command below
# reads it back from the cluster instead, for whoever already has cluster access.
output "api_key_check_command" {
  value       = "kubectl -n ${var.namespace} get secret ${var.secret_name} -o jsonpath='{.data.api-key}' | base64 -d"
  description = "Command reading the API key back out of the cluster. A command rather than the value, because every output is also written into the instance README that an unauthenticated code-server serves (rules.md H-2)"
}
output "agent_status_command" {
  value       = "kubectl -n ${var.namespace} get datadogagent ${var.agent_name} -o wide"
  description = "Command showing whether the operator accepted the DatadogAgent. This is the first place a wrong site or a missing Secret shows up"
}
output "agent_rollout_command" {
  value       = "kubectl -n ${var.namespace} rollout status daemonset ${var.agent_name}-agent"
  description = "Command confirming the agent DaemonSet rolled out on every node. The operator creates it from the DatadogAgent, so it does not exist until that resource is reconciled"
}
output "operator_logs_command" {
  value       = "kubectl -n ${var.namespace} logs deploy/${var.release_name} -f"
  description = "Command following the operator's log. Where a Secret in the wrong namespace or a rejected key explains itself - none of which surfaces as a Terraform error, because every object applied successfully"
}
