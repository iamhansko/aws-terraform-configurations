output "release_name" {
  value       = helm_release.node_termination_handler.name
  description = "Name of the release"
}
output "namespace" {
  value       = var.namespace
  description = "Namespace the handler runs in, re-exposed so the caller's diagnostic commands read one value (rules.md B-5)"
}
output "chart_version" {
  value       = var.chart_version
  description = "Version installed, pinned where the _monolithic template left it floating"
}
output "status_command" {
  value       = "kubectl -n ${var.namespace} get daemonset ${var.release_name} -o wide"
  description = "Whether a handler pod is on every node. desired and ready should match the node count - a node without one is a node that will disappear without being drained"
}
output "log_command" {
  value       = "kubectl -n ${var.namespace} logs -l app.kubernetes.io/name=aws-node-termination-handler --tail 100 --all-containers"
  description = "What the handler saw and did. A drain it performed is recorded here; on a Karpenter-provisioned node Karpenter's own log will show the same notice, which is the overlap the module's comment describes"
}
