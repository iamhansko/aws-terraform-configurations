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
