output "release_name" {
  value       = helm_release.karpenter.name
  description = "Name of the installed Karpenter Helm release"
}
output "release_status" {
  value       = helm_release.karpenter.status
  description = "Status of the installed Karpenter Helm release"
}
output "namespace" {
  value       = var.namespace
  description = "Namespace the Karpenter controller runs in, re-exposed so callers reference one source of truth (rules.md B-5)"
}
output "controller_role_arn" {
  value       = aws_iam_role.karpenter_controller_iam_role.arn
  description = "ARN of the IAM role the Karpenter controller assumes through IRSA"
}
output "node_role_arn" {
  value       = aws_iam_role.karpenter_node_iam_role.arn
  description = "ARN of the IAM role Karpenter-provisioned nodes run as"
}
output "node_role_name" {
  value       = aws_iam_role.karpenter_node_iam_role.name
  description = "Name of the IAM role Karpenter-provisioned nodes run as, which is also what EC2NodeClass.spec.role references"
}
output "controller_policy_arn" {
  value       = var.create_controller_policy ? aws_iam_policy.karpenter_controller_policy[0].arn : null
  description = "ARN of the least-privilege controller policy this module created, or null when the caller supplied its own. Exposed because the alternative - AdministratorAccess on the controller role - is the kind of thing worth being able to see in terraform output rather than having to read the module"
}
