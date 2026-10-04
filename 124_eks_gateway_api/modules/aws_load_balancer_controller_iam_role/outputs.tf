output "controller_role_arn" {
  value       = aws_iam_role.aws_load_balancer_controller_iam_role.arn
  description = "ARN of the controller's IRSA role, for the chart's serviceAccount.annotations eks.amazonaws.com/role-arn value"
}
output "controller_role_name" {
  value       = aws_iam_role.aws_load_balancer_controller_iam_role.name
  description = "Name of the controller's IRSA role"
}
output "namespace" {
  value       = var.namespace
  description = "Namespace named in the trust policy, re-exposed so the helm step installs into the same one rather than restating it (rules.md B-5). A mismatch between the two is not an error anywhere - the pod simply cannot assume the role"
}
output "service_account_name" {
  value       = var.service_account_name
  description = "Service account named in the trust policy, re-exposed for the same reason as namespace (rules.md B-5)"
}
output "policy_statement_count" {
  value       = length(jsondecode(local.iam_policy_document).Statement)
  description = "How many statements the embedded upstream policy has. Worth reading after bumping the controller version: the file is replaced wholesale, and this is the cheapest signal that the replacement is the document it should be"
}
