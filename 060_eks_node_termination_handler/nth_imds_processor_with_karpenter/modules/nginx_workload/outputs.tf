output "name" {
  value       = var.name
  description = "Name of the Deployment"
}
output "namespace" {
  value       = var.namespace
  description = "Namespace it runs in, re-exposed so the caller's diagnostic commands read one value (rules.md B-5)"
}
output "replicas" {
  value       = var.replicas
  description = "How many pods it runs, re-exposed so a caller describing the demo does not restate the number"
}
output "node_selector" {
  value       = var.node_selector
  description = "The labels these pods require, empty when they may run anywhere. Re-exposed so a mismatch with what a node pool actually applies is visible in terraform output rather than only as pods stuck Pending (rules.md B-5)"
}
output "rollout_status_command" {
  value       = "kubectl -n ${var.namespace} rollout status deployment ${var.name} --timeout=15m"
  description = "Waits for the pods. Long timeout on purpose: when the selector points at a Karpenter pool the first pods wait for an EC2 launch and a kubelet join rather than a schedule onto existing capacity"
}
output "pod_placement_command" {
  value       = "kubectl -n ${var.namespace} get pods -l app=${var.name} -o wide --sort-by=.spec.nodeName"
  description = "Which node each pod is on, sorted so the spread is readable. Run it before and after an interruption: the pods that were on the interrupted node should reappear elsewhere, and the count should return to the replica count"
}
output "node_list_command" {
  value       = "kubectl get nodes -L eks.amazonaws.com/capacityType,karpenter.sh/capacity-type,node.kubernetes.io/instance-type"
  description = "Every node with whether it is spot or on-demand, from both the managed node group's label and Karpenter's. This is the before-and-after view for an interruption"
}
output "drain_events_command" {
  value       = "kubectl get events --all-namespaces --field-selector reason=NodeNotSchedulable,reason=Killing --sort-by=.lastTimestamp"
  description = "The cordon and the evictions, in order. This is the record that the handler acted rather than the node simply vanishing - an instance reclaimed without a drain leaves no such events"
}
