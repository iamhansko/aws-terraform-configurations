output "release_name" {
  value       = helm_release.aws_load_balancer_controller.name
  description = "Name of the installed aws-load-balancer-controller Helm release"
}
output "release_status" {
  value       = helm_release.aws_load_balancer_controller.status
  description = "Status of the installed aws-load-balancer-controller Helm release"
}
output "controller_role_arn" {
  value       = aws_iam_role.aws_load_balancer_controller_iam_role.arn
  description = "ARN of the IAM role the controller assumes through IRSA"
}
output "namespace" {
  value       = var.namespace
  description = "Namespace the controller runs in, re-exposed so callers waiting on it reference one source of truth (rules.md #5)"
}
output "service_account_name" {
  value       = var.service_account_name
  description = "Service account name the controller runs as, re-exposed for the same reason as namespace (rules.md #5)"
}
