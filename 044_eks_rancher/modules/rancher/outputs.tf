output "release_name" {
  value       = helm_release.rancher.name
  description = "Name of the Helm release"
}
output "namespace" {
  value       = var.namespace
  description = "Namespace Rancher runs in, re-exposed so callers do not restate it (rules.md B-5)"
}
output "hostname" {
  value       = var.hostname
  description = "The host Rancher serves on, re-exposed so a mismatch with the load balancer that actually fronts it is visible in outputs (rules.md B-5)"
}
output "dashboard_url" {
  value       = "https://${var.hostname}/dashboard/"
  description = "Rancher dashboard URL. https because Rancher terminates TLS with a cert-manager certificate; the certificate is self-signed, so a browser warning on first visit is expected rather than a fault"
}
output "bootstrap_password_command" {
  value       = "kubectl -n ${var.namespace} get secret bootstrap-secret -o jsonpath='{.data.bootstrapPassword}' | base64 -d"
  description = "Command reading the bootstrap password back out of the cluster. A command rather than the value, because the _monolithic template embedded it in the dashboard URL and that URL is written into the instance README, which an unauthenticated code-server serves (rules.md H-2)"
}
output "check_command" {
  value       = "kubectl -n ${var.namespace} rollout status deployment ${var.release_name}"
  description = "Command confirming the Rancher server finished rolling out"
}
