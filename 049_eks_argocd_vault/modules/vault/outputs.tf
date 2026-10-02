output "release_name" {
  value       = helm_release.vault.name
  description = "Name of the Helm release"
}
output "chart_version" {
  value       = var.chart_version
  description = "Pinned chart version, re-exposed so what is installed is visible without reading the module (rules.md B-5)"
}
output "namespace" {
  value       = var.namespace
  description = "Namespace Vault runs in, re-exposed so callers do not restate it (rules.md B-5)"
}
output "stack_tag" {
  value       = "${var.namespace}/${var.release_name}"
  description = "The <namespace>/<name> value the AWS Load Balancer Controller writes into its ingress.k8s.aws/stack tag for the Vault Ingress. A pre-created load balancer must carry exactly this to be adopted rather than duplicated (rules.md B-5/G-3)"
}
output "pod_name" {
  value       = "${var.release_name}-0"
  description = "Name of the first Vault pod. The bootstrap association execs into it, so the name is derived here rather than restated in the shell (rules.md B-5)"
}
output "internal_address" {
  value       = "http://${var.release_name}.${var.namespace}:8200"
  description = "In-cluster address of Vault, which is what the argocd-vault-plugin is pointed at. Derived from the release name and namespace so it cannot drift from where Vault actually is"
}
output "ingress_command" {
  value       = "kubectl -n ${var.namespace} get ingress -o wide"
  description = "Command showing the Vault Ingress and whether the controller gave it an address. An empty ADDRESS means no controller is reconciling it - and an Ingress that does not exist at all means the chart ignored the ingress values, which is what happens when they are set at the top level instead of under server (rules.md G-3)"
}
output "status_command" {
  value       = "kubectl -n ${var.namespace} exec ${var.release_name}-0 -- vault status"
  description = "Command showing whether Vault is initialised and unsealed. Sealed or uninitialised is the expected state until the bootstrap association has run"
}
