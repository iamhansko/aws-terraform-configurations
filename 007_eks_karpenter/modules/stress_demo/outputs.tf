output "name" {
  value       = var.name
  description = "Name of the demo Deployment, re-exposed so callers build commands from one source of truth (rules.md B-5)"
}
output "namespace" {
  value       = var.namespace
  description = "Namespace the demo Deployment runs in"
}
output "node_selector" {
  value       = var.node_selector
  description = "Labels the demo pods require of a node, re-exposed so the caller can confirm it matches the NodePool it came from"
}
output "scale_up_command" {
  value       = "kubectl -n ${var.namespace} scale deployment ${var.name} --replicas ${var.demo_replica_count}"
  description = "Creates pods no existing node can fit, so Karpenter provisions capacity. Watch it happen with the nodes_watch_command below"
}
output "scale_down_command" {
  value       = "kubectl -n ${var.namespace} scale deployment ${var.name} --replicas 0"
  description = "Removes the pods again, leaving the nodes empty so Karpenter consolidates them away after the NodePool's consolidateAfter window"
}
output "nodes_watch_command" {
  value       = "kubectl get nodes -L ${join(",", keys(var.node_selector))} --watch"
  description = "Watches nodes appear and disappear, with the NodePool's labels shown as columns so Karpenter-provisioned nodes are distinguishable from the managed node group"
}
output "pods_watch_command" {
  value       = "kubectl -n ${var.namespace} get pods -o wide --watch"
  description = "Watches the demo pods move from Pending to Running as Karpenter's nodes join the cluster"
}
