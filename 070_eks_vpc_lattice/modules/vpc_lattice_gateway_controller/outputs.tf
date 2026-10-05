output "release_name" {
  value       = helm_release.gateway_api_controller.name
  description = "Name of the Helm release"
}
output "namespace" {
  value       = var.namespace
  description = "Namespace the controller runs in, re-exposed so the caller's diagnostic commands read one value (rules.md B-5)"
}
output "role_arn" {
  value       = aws_iam_role.gateway_api_controller.arn
  description = "ARN of the controller's IAM role"
}
output "service_account" {
  value       = var.service_account_name
  description = "The service account the Pod Identity association binds, re-exposed so a caller checking the association names the same value the module used (rules.md B-5)"
}
output "default_service_network" {
  value       = var.default_service_network
  description = "The VPC Lattice service network the controller creates, re-exposed because a Gateway is paired with it by name - and a mismatch produces a Gateway that never gets an address, with nothing reporting why (rules.md B-5)"
}
output "chart_version" {
  value       = var.chart_version
  description = "The pinned chart version, re-exposed so it can be checked against the Gateway API release installed alongside it"
}
output "logs_command" {
  value       = "kubectl -n ${var.namespace} logs deploy/${var.release_name} --tail 100"
  description = "The controller's own log. Every reason a Gateway or HTTPRoute produced no Lattice resources is here: an AccessDenied means the Pod Identity association or the policy, and a reconcile error names the object it could not build"
}
output "pod_identity_check_command" {
  value       = "aws eks list-pod-identity-associations --cluster-name ${var.cluster_name} --query 'associations[?serviceAccount==`${var.service_account_name}`]' --output table"
  description = "Whether the association exists and binds the account the chart actually created. A controller with no credentials logs AccessDenied and keeps retrying, so the Helm release still reports success"
}
output "service_network_check_command" {
  value       = "aws vpc-lattice list-service-networks --query 'items[].[name,id,status]' --output table"
  description = "The service network on the AWS side. This is the first thing the controller creates, so an empty list means it has not managed a single call - check its log and its credentials before looking at any Kubernetes object"
}
