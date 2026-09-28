output "node_group_arn" {
  value       = aws_eks_node_group.app_node_group.arn
  description = "ARN of the EKS managed node group"
}

output "node_role_arn" {
  value       = aws_iam_role.eks_node_iam_role.arn
  description = "ARN of the node group's IAM role"
}

output "node_group_name" {
  value       = aws_eks_node_group.app_node_group.node_group_name
  description = "Name of the EKS managed node group, re-exposed so the caller's verification commands read one value rather than restating the variable (rules.md B-5)"
}

output "autoscaling_group_names" {
  # EKS creates the Auto Scaling group itself and reports it back through the node group's resources
  # attribute. Nothing in this configuration declares it, which is the point of a managed node group -
  # and the reason its name can only be read from here.
  value       = [for g in aws_eks_node_group.app_node_group.resources[0].autoscaling_groups : g.name]
  description = "Names of the Auto Scaling groups EKS created for this node group"
}
