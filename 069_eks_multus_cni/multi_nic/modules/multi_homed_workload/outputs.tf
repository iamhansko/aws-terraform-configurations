output "name" {
  value       = var.name
  description = "Name of the Deployment"
}
output "namespace" {
  value       = var.namespace
  description = "Namespace it runs in, re-exposed so the caller's diagnostic commands read one value (rules.md B-5)"
}
output "multi_nic_requested" {
  value       = var.enable_multi_nic_annotation
  description = "Whether the pod template carries the nicConfig annotation, re-exposed because it is the only difference between a pod with two interfaces and a pod with one - and nothing in the cluster reports which case you are in (rules.md B-5)"
}
output "rollout_status_command" {
  value       = "kubectl -n ${var.namespace} rollout status deployment ${var.name} --timeout=10m"
  description = "Waits for the pod. Slower than it looks on a multi-NIC cluster: with the feature on, the VPC CNI stops allocating addresses in bulk and assigns them on demand, so the first pod on a node waits for an address rather than taking a pre-warmed one"
}
output "interface_list_command" {
  value       = "kubectl -n ${var.namespace} exec deploy/${var.name} -- ip -brief address"
  description = "The whole demo in one command. Two addresses besides loopback means the second network card was used; one means it was not - and that is the same picture a cluster without ENABLE_MULTI_NIC, or a node with a single network card, produces"
}
output "pod_placement_command" {
  value       = "kubectl -n ${var.namespace} get pods -l app=${var.name} -o wide"
  description = "Which node the pod landed on, which is what to check first when it has only one interface: a node whose instance type has a single network card cannot give it a second one"
}
output "cni_log_command" {
  value       = "kubectl -n kube-system logs -l k8s-app=aws-node -c aws-node --tail 50"
  description = "The VPC CNI's own log on the node. This is where a multi-NIC attachment is either recorded or absent, and the only place that distinguishes \"the feature is off\" from \"the annotation was not seen\""
}
