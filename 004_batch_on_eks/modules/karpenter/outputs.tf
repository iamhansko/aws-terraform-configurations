output "release_name" {
  value       = helm_release.karpenter.name
  description = "Name of the installed Karpenter Helm release"
}

output "release_status" {
  value       = helm_release.karpenter.status
  description = "Status of the installed Karpenter Helm release"
}

output "controller_role_arn" {
  value       = aws_iam_role.karpenter_controller_iam_role.arn
  description = "ARN of the Karpenter controller's IAM role (assumed via IRSA)"
}

output "node_role_arn" {
  value       = aws_iam_role.karpenter_node_iam_role.arn
  description = "ARN of the IAM role used by Karpenter-provisioned nodes"
}
output "controller_policy_arn" {
  value       = var.create_controller_policy ? aws_iam_policy.karpenter_controller_policy[0].arn : null
  description = "ARN of the least-privilege controller policy this module created, or null when the caller supplied its own. Exposed because the alternative - AdministratorAccess on the controller role - is the kind of thing worth being able to see in terraform output rather than having to read the module"
}
