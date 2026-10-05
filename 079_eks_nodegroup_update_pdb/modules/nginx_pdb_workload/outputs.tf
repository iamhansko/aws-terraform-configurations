output "name" {
  value       = var.name
  description = "Name of the Deployment and of the budget"
}
output "namespace" {
  value       = var.namespace
  description = "Namespace both objects live in, re-exposed so the caller's diagnostic commands read one value (rules.md B-5)"
}
output "replicas" {
  value       = var.replicas
  description = "How many pods it runs, re-exposed so a caller describing the demo does not restate the number"
}
output "budget" {
  value       = var.pdb_max_unavailable == null ? "minAvailable=${var.pdb_min_available}" : "maxUnavailable=${var.pdb_max_unavailable}"
  description = "The budget in force, rendered the way the object states it. Re-exposed because this is the number that decides how long the node group update takes, and reading it off the module keeps the caller from describing a budget it did not set (rules.md B-5)"
}
output "readiness_initial_delay_seconds" {
  value       = var.readiness_initial_delay_seconds
  description = "How long a replacement pod stays NotReady, re-exposed for the same reason: together with the budget it sets the floor on how long each eviction step of the update takes"
}
output "rollout_status_command" {
  value       = "kubectl -n ${var.namespace} rollout status deployment ${var.name} --timeout=10m"
  description = "Waits for all pods to turn Ready. Run it before starting the update: with a sixty-second readiness delay the Deployment is not settled for at least that long after apply, and starting the update early makes the budget block on pods that were never Ready in the first place"
}
output "pod_placement_command" {
  value       = "kubectl -n ${var.namespace} get pods -l app=${var.name} -o wide --sort-by=.spec.nodeName"
  description = "Which node each pod sits on, sorted so the spread is readable. Run it before the update and again during: pods should move off the node being replaced one at a time, never two at once"
}
output "pdb_status_command" {
  value       = "kubectl -n ${var.namespace} get pdb ${var.name} -o wide"
  description = "The budget's live accounting: ALLOWED DISRUPTIONS is the number that gates the drain. It reads 1 while all pods are Ready and drops to 0 the moment one is evicted, which is the update waiting rather than the update being stuck"
}
output "pdb_events_command" {
  value       = "kubectl -n ${var.namespace} describe pdb ${var.name}"
  description = "The same accounting with the controller's events. A budget whose selector matches nothing reports its status without complaint here, which is the failure worth ruling out first - an unmatched budget allows every disruption and the update proceeds as if no budget existed"
}
output "eviction_events_command" {
  value       = "kubectl get events --all-namespaces --field-selector reason=Evicted,reason=NodeNotSchedulable --sort-by=.lastTimestamp"
  description = "The cordons and the evictions in the order they happened. This is the record that EKS drained each node rather than terminating it: a forced update deletes pods instead of evicting them, and leaves no eviction events at all"
}
