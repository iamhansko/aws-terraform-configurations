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
output "node_tags" {
  value       = var.node_tags
  description = "AWS tags Karpenter writes onto the instances this pool provisions, re-exposed because the FIS experiments find their targets by the Name tag among them - a mismatch means an experiment that resolves to no instances (rules.md B-5)"
}
output "node_name_tag" {
  value       = lookup(var.node_tags, "Name", null)
  description = "Just the Name tag, or null if the pool sets none. This is the value a FIS target's resource_tag has to match, pulled out on its own so the caller passes one string rather than digging into a map (rules.md B-5)"
}
