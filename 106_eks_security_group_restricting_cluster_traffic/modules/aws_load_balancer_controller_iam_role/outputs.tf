output "controller_role_arn" {
  value       = aws_iam_role.aws_load_balancer_controller_iam_role.arn
  description = "ARN of the IRSA role the controller's service account assumes. The caller interpolates this into the helm command the bastion runs, because the chart is installed there rather than by a helm provider (see main.tf)"
}
output "controller_role_name" {
  value       = aws_iam_role.aws_load_balancer_controller_iam_role.name
  description = "Name of the IRSA role"
}
output "namespace" {
  value       = var.namespace
  description = "Namespace the controller's service account lives in, re-exposed so the caller's helm command does not restate it (rules.md B-5)"
}
output "service_account_name" {
  value       = var.service_account_name
  description = "Service account name the role's trust policy is scoped to. The helm command must create a service account with exactly this name, or the role's condition never matches and every AWS call the controller makes is denied (rules.md B-5)"
}

output "pod_identity_association_id" {
  value       = aws_eks_pod_identity_association.aws_load_balancer_controller.association_id
  description = "ID of the association binding the controller's service account to the role. Its existence is what makes the chart install need no role-arn annotation on the service account at all"
}
