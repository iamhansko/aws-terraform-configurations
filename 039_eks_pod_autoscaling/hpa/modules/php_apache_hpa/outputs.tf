output "name" {
  value       = var.name
  description = "Name of the Deployment, Service and HorizontalPodAutoscaler"
}
output "namespace" {
  value       = var.namespace
  description = "Namespace the workload runs in, re-exposed so the caller does not restate it (rules.md B-5)"
}
output "replica_range" {
  value       = "${var.min_replicas}-${var.max_replicas}"
  description = "Replica range the HPA keeps the Deployment within"
}
output "target_cpu_utilization_percentage" {
  value       = var.target_cpu_utilization_percentage
  description = "CPU utilisation target the HPA holds, as a percentage of the container's CPU request"
}
output "cpu_request" {
  value       = var.cpu_request
  description = "CPU request the HPA measures utilisation against. Exposed because the target percentage is meaningless without it: 60% of 200m is 120m, and that is the number the load generator has to push past"
}
output "hpa_watch_command" {
  value       = "kubectl -n ${var.namespace} get hpa ${var.name} --watch"
  description = "Command watching the HPA's observed utilisation and replica count. A TARGETS column reading <unknown> means metrics-server is not answering, not that the load is too low"
}
output "load_generator_command" {
  value       = "kubectl -n ${var.namespace} run load-generator --image=busybox --restart=Never -- /bin/sh -c 'while true; do wget -q -O - http://${var.name}; done'"
  description = "Command creating the pod that drives the demo. It requests the Service by name in a tight loop, which is what pushes measured CPU past the target"
}
output "load_generator_cleanup_command" {
  value       = "kubectl -n ${var.namespace} delete pod load-generator"
  description = "Command removing the load generator. The HPA then scales back down, though not immediately - it holds the higher count through a stabilisation window of about five minutes by default"
}
output "pods_command" {
  value       = "kubectl -n ${var.namespace} get pods -l run=${var.name} -o wide"
  description = "Command listing the workload's pods and the nodes they landed on. With max replicas above what the node group can hold, some are expected to sit Pending"
}
