output "release_name" {
  value       = helm_release.cluster_proportional_autoscaler.name
  description = "Name of the Helm release"
}
output "namespace" {
  value       = helm_release.cluster_proportional_autoscaler.namespace
  description = "Namespace the autoscaler runs in"
}
output "chart_version" {
  value       = helm_release.cluster_proportional_autoscaler.version
  description = "Chart version installed, re-exposed so the pinned value is visible without reading the module (rules.md B-5)"
}
output "target" {
  value       = var.target
  description = "The workload the autoscaler resizes, re-exposed so a caller building a kubectl command does not restate it (rules.md B-5)"
}
output "replica_range" {
  value       = "${var.min_replicas}-${var.max_replicas}"
  description = "Replica range the autoscaler keeps the target within"
}
output "nodes_per_replica" {
  value       = var.nodes_per_replica
  description = "Nodes per replica of the target, the slope of the linear ladder"
}
output "configmap_command" {
  value       = "kubectl -n ${var.namespace} get configmap ${var.release_name} -o jsonpath='{.data.linear}'"
  description = "Command printing the ladder the autoscaler is actually using. Booleans must appear unquoted here: a quoted \"true\" is valid JSON the autoscaler cannot unmarshal (rules.md E-7)"
}
