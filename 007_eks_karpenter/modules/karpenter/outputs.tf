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
output "node_class_name" {
  value       = var.node_class_name
  description = "Name of the EC2NodeClass, re-exposed so a second NodePool declared elsewhere can reference it (rules.md B-5)"
}
output "node_pool_name" {
  value       = var.node_pool_name
  description = "Name of the NodePool Karpenter provisions against"
}
output "node_labels" {
  value       = var.node_labels
  description = "Labels every node this NodePool provisions carries, re-exposed so a workload's nodeSelector references the same map the pool was given instead of restating it (rules.md B-5)"
}
output "instance_types" {
  value       = var.instance_types
  description = "Exact instance types the NodePool is pinned to, or an empty list when Karpenter is free to choose within the category and generation requirements"
}
