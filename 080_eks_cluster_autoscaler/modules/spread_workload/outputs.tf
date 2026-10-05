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
  description = "How many pods it asks for, re-exposed so a caller describing the demo states the number that was actually configured (rules.md B-5)"
}
output "topology_key" {
  value       = var.topology_key
  description = "The node label its replicas are spread across, re-exposed because it is the only field that differs between the two instances of this module and therefore the only thing a caller needs to tell them apart"
}
output "total_cpu_request" {
  value       = "${var.replicas} x ${var.cpu_request}"
  description = "The demand this Deployment puts on the cluster, which is what the autoscaler is actually reacting to. Stated as the product rather than as a total because the request is a Kubernetes quantity string rather than a number"
}
output "pod_placement_command" {
  value       = "kubectl -n ${var.namespace} get pods -l app=${var.name} -o wide --sort-by=.spec.nodeName"
  description = "Which node each pod landed on, sorted so the spread is readable. Pods still Pending here are what the autoscaler is working on"
}
output "pod_distribution_command" {
  value       = "kubectl -n ${var.namespace} get pods -l app=${var.name} -o custom-columns=NODE:.spec.nodeName --no-headers | sort | uniq -c"
  description = "The same placement counted per node, which is the quickest way to see whether the spread constraint did anything. Deliberately built from kubectl and coreutils rather than jq, which is not installed on the workbench instance"
}
output "pending_pods_command" {
  value       = "kubectl -n ${var.namespace} get pods -l app=${var.name} --field-selector status.phase=Pending"
  description = "Only the pods that have nowhere to go. This list being non-empty is the input to a scale-up; it emptying without new nodes appearing means the pods fitted after all"
}
