# Every output is a projection of local.outputs in main.tf, which is also what
# the README on the instance is rendered from (rules.md H-2). No value
# expression is written here: an output that built its own value would be
# missing from that README, and nothing would fail to tell anyone.
#
# description is the one thing repeated, because Terraform rejects an expression
# there ("Variables not allowed") - it has to be a literal.
output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "URL to reach code-server: the CloudFront HTTPS URL when enable_cloudfront is true, otherwise the instance's public IP on the code-server port"
}
output "cluster_name" {
  value       = local.outputs.cluster_name.value
  description = "Name of the EKS cluster"
}
output "cluster_endpoint" {
  value       = local.outputs.cluster_endpoint.value
  description = "API server endpoint of the EKS cluster"
}
output "node_group_name" {
  value       = local.outputs.node_group_name.value
  description = "Name of the managed node group hosting the Karpenter controller"
}
output "karpenter_node_role_name" {
  value       = local.outputs.karpenter_node_role_name.value
  description = "Name of the IAM role Karpenter-provisioned nodes run as, which EC2NodeClass.spec.role references"
}
output "karpenter_node_pool_name" {
  value       = local.outputs.karpenter_node_pool_name.value
  description = "Name of the NodePool Karpenter provisions against"
}
output "karpenter_node_labels" {
  value       = local.outputs.karpenter_node_labels.value
  description = "Labels every Karpenter-provisioned node carries, as comma-separated key=value pairs, which is also what the stress demo's nodeSelector requires"
}
output "karpenter_instance_types" {
  value       = local.outputs.karpenter_instance_types.value
  description = "Instance types the NodePool is pinned to, or an empty string when Karpenter may choose freely within its category and generation requirements"
}
output "stress_demo_name" {
  value       = local.outputs.stress_demo_name.value
  description = "Name of the demo Deployment declared at zero replicas, ready to be scaled up to make Karpenter provision nodes"
}
output "stress_demo_scale_up_command" {
  value       = local.outputs.stress_demo_scale_up_command.value
  description = "Creates pods that no existing node can fit, so Karpenter provisions new capacity"
}
output "stress_demo_nodes_watch_command" {
  value       = local.outputs.stress_demo_nodes_watch_command.value
  description = "Watches nodes join and leave while the demo scales, with the NodePool's labels as columns"
}
output "stress_demo_pods_watch_command" {
  value       = local.outputs.stress_demo_pods_watch_command.value
  description = "Watches the demo pods move from Pending to Running as Karpenter's nodes become Ready"
}
output "stress_demo_scale_down_command" {
  value       = local.outputs.stress_demo_scale_down_command.value
  description = "Removes the demo pods again, leaving Karpenter's nodes empty so consolidation deletes them"
}
