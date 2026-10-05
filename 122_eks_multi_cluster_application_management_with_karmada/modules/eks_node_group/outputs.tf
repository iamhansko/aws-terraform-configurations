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
  description = "Kubernetes labels applied to this node group's nodes, re-exposed so callers scheduling pods onto it reference one source of truth (rules.md B-5)"
}
output "autoscaling_group_name" {
  value       = aws_eks_node_group.eks_node_group.resources[0].autoscaling_groups[0].name
  description = <<-DESC
    Name of the Auto Scaling group EKS created for this node group. A managed node group always has exactly
    one, which is why this is a single value rather than the list the attribute nests it in.

    Needed because a load balancer target group registers these nodes through an aws_autoscaling_attachment
    rather than one aws_lb_target_group_attachment per instance: the Auto Scaling group then keeps the
    registration correct as nodes are replaced, which a per-instance attachment would not - and per-instance
    attachments are not expressible anyway, because the instance IDs are not known until apply and so cannot
    be for_each keys (rules.md B-8).
  DESC
}
