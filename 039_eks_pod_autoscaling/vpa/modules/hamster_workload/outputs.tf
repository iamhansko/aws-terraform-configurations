output "name" {
  value       = var.name
  description = "Name of the Deployment"
}
output "namespace" {
  value       = var.namespace
  description = "Namespace the workload runs in, re-exposed so the caller does not restate it (rules.md B-5)"
}
output "vpa_name" {
  value       = local.vpa_name
  description = "Name of the VerticalPodAutoscaler, derived from the Deployment name here rather than restated by the caller (rules.md B-5)"
}
output "update_mode" {
  value       = var.update_mode
  description = "What the VPA is allowed to do with its recommendation. Off records it only; Auto also evicts pods to apply it"
}
output "initial_requests" {
  value       = "cpu ${var.cpu_request}, memory ${var.memory_request}"
  description = "The requests the pods start with. Worth keeping in view: the demo is the distance between these and the recommendation"
}
output "allowed_range" {
  value       = "cpu ${var.min_allowed_cpu}-${var.max_allowed_cpu}, memory ${var.min_allowed_memory}-${var.max_allowed_memory}"
  description = "Bounds the VPA must keep its recommendation inside"
}
output "recommendation_command" {
  value       = "kubectl -n ${var.namespace} describe vpa ${local.vpa_name}"
  description = "Command showing what the recommender decided. The Target figures under Recommendation are what the admission controller writes onto replacement pods. Empty for the first few minutes - the recommender needs a usage history before it has an opinion"
}
output "applied_requests_command" {
  value       = "kubectl -n ${var.namespace} get pods -l app=${var.name} -o custom-columns=NAME:.metadata.name,CPU_REQ:.spec.containers[0].resources.requests.cpu,MEM_REQ:.spec.containers[0].resources.requests.memory,AGE:.metadata.creationTimestamp"
  description = "Command showing the requests the running pods actually have. This is where the demo lands: once the updater has evicted a pod, its replacement comes back with the recommended requests rather than the ones in the Deployment"
}
output "eviction_events_command" {
  value       = "kubectl -n ${var.namespace} get events --field-selector reason=EvictedByVPA --sort-by=.lastTimestamp"
  description = "Command listing the updater's evictions, which is the mechanism behind the change above. No events means the recommendation is still close enough to the current requests for the updater to leave the pods alone"
}
