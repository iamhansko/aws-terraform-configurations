output "namespace" {
  value       = var.namespace
  description = "Namespace cert-manager runs in, re-exposed so the caller's diagnostic commands read one value (rules.md B-5)"
}
output "release_name" {
  value       = var.release_name
  description = "Name of the release, which is also the service account name the IRSA trust policy is written against"
}
output "chart_version" {
  value       = var.chart_version
  description = "Version installed, re-exposed so the CRD generation in the cluster is visible in terraform output (rules.md B-5)"
}
output "iam_role_arn" {
  value       = aws_iam_role.cert_manager_iam_role.arn
  description = "IRSA role the controller assumes to write DNS-01 challenge records. Scoped to one hosted zone, where the _monolithic template put the same permissions on the node instance role and so gave them to every pod on the cluster"
}
output "issuer_name" {
  value       = var.issuer_name
  description = "Name of the ClusterIssuer. Consumers reference an issuer by name, so this is passed on rather than restated (rules.md B-5)"
}
output "issuer_kind" {
  value       = "ClusterIssuer"
  description = "Kind consumers must reference. A namespaced Issuer would need the controller started with --issuer-ambient-credentials before it could use the IRSA identity, which is why this module creates the cluster-scoped form (rules.md B-5)"
}
output "issuer_status_command" {
  value       = "kubectl get clusterissuer ${var.issuer_name} -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].message}'"
  description = "Whether the ACME account registered. A failure here is usually the email or the ACME server, and it stops every certificate in the cluster before any challenge is attempted"
}
output "certificate_status_command" {
  value       = "kubectl get certificate,certificaterequest,order,challenge -A"
  description = "The whole issuance chain in one command. cert-manager creates these in order, so the last object present is where it stopped - a Challenge stuck Pending means the DNS-01 record could not be written or has not propagated"
}
output "controller_log_command" {
  value       = "kubectl -n ${var.namespace} logs deploy/${var.release_name} --tail 100"
  description = "Where a rejected AssumeRoleWithWebIdentity or a Route 53 AccessDenied appears. Neither shows up on the Certificate object, which simply stays Pending"
}
