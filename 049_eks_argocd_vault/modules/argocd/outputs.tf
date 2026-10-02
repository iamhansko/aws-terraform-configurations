output "release_name" {
  value       = helm_release.argocd.name
  description = "Name of the Helm release"
}
output "chart_version" {
  value       = var.chart_version
  description = "Pinned chart version, re-exposed so what is installed is visible without reading the module (rules.md B-5)"
}
output "namespace" {
  value       = var.namespace
  description = "Namespace Argo CD runs in, re-exposed so callers do not restate it (rules.md B-5)"
}
output "server_service_name" {
  value       = "${var.release_name}-server"
  description = "Name of the Service the chart creates for the Argo CD UI, derived from the release name the chart derives it from"
}
output "stack_tag" {
  value       = "${var.namespace}/${var.release_name}-server"
  description = "The <namespace>/<name> value the AWS Load Balancer Controller writes into its service.k8s.aws/stack tag for the server Service. A pre-created load balancer must carry exactly this to be adopted rather than duplicated (rules.md B-5/G-3)"
}
output "plugin_name" {
  value       = var.plugin_name
  description = "Name of the ConfigManagementPlugin an Application has to ask for with --config-management-plugin"
}
output "vault_secret_name" {
  value       = var.vault_secret_name
  description = "Name of the Secret the plugin reads Vault's address and token from, re-exposed so the bootstrap step and the Role cannot disagree about it (rules.md B-5)"
}
output "hostname_command" {
  value       = "kubectl -n ${var.namespace} get service ${var.release_name}-server -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
  description = "Command reading the address the controller actually attached. Worth comparing against the pre-created load balancer's DNS name: if they differ, adoption failed and there are now two load balancers (rules.md G-3)"
}
output "initial_password_command" {
  value       = "kubectl -n ${var.namespace} get secret ${var.release_name}-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
  description = "Command reading Argo CD's generated admin password. A command rather than a value, because the chart generates it and every output here is written into a README an unauthenticated code-server serves (rules.md H-2)"
}
output "repo_server_rollout_command" {
  value       = "kubectl -n ${var.namespace} rollout status deployment ${var.release_name}-repo-server"
  description = "Command confirming the repo-server rolled out with its sidecar. This is the pod that has to come up for the plugin to work, and its init container pulls the plugin binary over the internet - so it is the slowest part of the release"
}
output "plugin_logs_command" {
  value       = "kubectl -n ${var.namespace} logs deploy/${var.release_name}-repo-server -c ${var.sidecar_name} --tail 100"
  description = "Command following the plugin sidecar's log. Where a Vault token that was never written, or a Secret the Role does not grant, explains itself - neither of which is a Terraform error"
}
