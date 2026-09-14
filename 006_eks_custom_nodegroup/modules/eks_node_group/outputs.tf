output "node_group_name" {
  value       = aws_eks_node_group.eks_node_group.node_group_name
  description = "Name of the EKS managed node group"
}
output "node_group_arn" {
  value       = aws_eks_node_group.eks_node_group.arn
  description = "ARN of the EKS managed node group"
}
output "node_role_arn" {
  value       = aws_iam_role.eks_node_iam_role.arn
  description = "ARN of the node group's IAM role"
}
output "node_role_name" {
  value       = aws_iam_role.eks_node_iam_role.name
  description = "Name of the node group's IAM role, for attaching extra policies from the root module"
}
output "launch_template_id" {
  value       = aws_launch_template.eks_node_launch_template.id
  description = "ID of the launch template backing the node group"
}
output "labels" {
  value       = var.labels
  description = "Kubernetes labels applied to this node group's nodes, re-exposed so callers scheduling pods onto it reference one source of truth (rules.md #5)"
}
