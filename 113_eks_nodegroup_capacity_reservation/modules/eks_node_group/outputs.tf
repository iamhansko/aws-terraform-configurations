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
output "autoscaling_group_names" {
  value       = [for group in aws_eks_node_group.eks_node_group.resources[0].autoscaling_groups : group.name]
  description = "Names of the Auto Scaling groups EKS created behind this node group. The _monolithic template reached these through a Lambda-backed CloudFormation custom resource that called eks:DescribeNodegroup; the provider exposes them directly, so the Lambda, its role and its policy are all unnecessary"
}
output "instance_tags" {
  value       = var.instance_tags
  description = "The extra instance tags this node group applies, re-exposed so a caller matching on one of them (a Node Termination Handler managed-tag filter, say) reads the same value the launch template wrote (rules.md B-5)"
}
output "update_strategy" {
  value       = var.update_strategy
  description = "How EKS replaces this group's nodes, re-exposed because it is the difference between a launch template change that completes and one that waits on reserved capacity that cannot appear (rules.md B-5)"
}
