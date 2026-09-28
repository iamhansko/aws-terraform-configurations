output "release_name" {
  value       = helm_release.cert_manager.name
  description = "Name of the Helm release"
}
output "namespace" {
  value       = var.namespace
  description = "Namespace cert-manager runs in, re-exposed so callers do not restate it (rules.md B-5)"
}
output "check_command" {
  value       = "kubectl -n ${var.namespace} get pods"
  description = "Command listing the cert-manager pods. All three (controller, webhook, cainjector) have to be Running before anything can create a Certificate"
}
