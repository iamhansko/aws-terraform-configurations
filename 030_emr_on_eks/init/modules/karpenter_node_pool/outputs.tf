output "name" {
  value       = var.name
  description = "Name of the NodePool and its EC2NodeClass, re-exposed so callers do not restate it (rules.md B-5)"
}

output "node_labels" {
  value       = var.node_labels
  description = "Labels this pool's nodes carry. A workload's nodeSelector is built from this rather than from a literal map, so a selector that matches no pool is not expressible (rules.md B-5)"
}

output "taints" {
  value       = var.taints
  description = "Taints this pool's nodes carry, re-exposed so a workload can derive its tolerations from them instead of restating key, value and effect"
}

output "node_pool_status_command" {
  value       = "kubectl get nodepool ${var.name} -o wide"
  description = "Command that shows the pool and how much it has provisioned. A pool with zero nodes and a pending pod usually means the pod's nodeSelector does not match node_labels, or its resource request exceeds every allowed instance size"
}

output "nodes_command" {
  value       = "kubectl get nodes -l ${join(",", [for key, value in var.node_labels : "${key}=${value}"])} -o wide"
  description = "Command that lists only the nodes this pool provisioned, selected by the pool's own labels"
}
