output "node_group_arn" {
  value       = aws_eks_node_group.app_node_group.arn
  description = "ARN of the EKS managed node group"
}

output "node_role_arn" {
  value       = aws_iam_role.eks_node_iam_role.arn
  description = "ARN of the node group's IAM role"
}
