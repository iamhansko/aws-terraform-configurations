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
output "launch_template_name" {
  value       = aws_launch_template.eks_node_launch_template.name
  description = "Name of the launch template backing the node group"
}
output "launch_template_latest_version" {
  value       = aws_launch_template.eks_node_launch_template.latest_version
  description = "Newest version of the launch template. Differs from launch_template_version whenever a new version has been created but the node group has not adopted it, which is the state an available node group update looks like"
}
output "launch_template_version" {
  value       = aws_eks_node_group.eks_node_group.launch_template[0].version
  description = "Launch template version the node group is actually running. Read back off the node group rather than from the variable, so it reflects what EKS was told even when the caller left the version to follow latest (rules.md B-5)"
}
output "force_update_version" {
  value       = var.force_update_version
  description = "Whether this node group's updates bypass PodDisruptionBudgets, re-exposed because it decides whether a budget can affect an update at all - and a forced update looks exactly like a cluster with no budgets (rules.md B-5)"
}
output "update_max_unavailable" {
  value       = var.update_max_unavailable_percentage == null ? tostring(var.update_max_unavailable) : "${var.update_max_unavailable_percentage}%"
  description = "How many nodes the upgrade phase takes out of service at once, as a count or a percentage depending on which was set. Re-exposed so a caller describing the update reads the value EKS was given"
}
