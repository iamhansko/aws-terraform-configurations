output "name" {
  value       = var.name
  description = "Name of the Deployment, re-exposed so callers do not restate it (rules.md B-5)"
}

output "namespace" {
  value       = var.namespace
  description = "Namespace the Deployment lives in"
}

output "replicas" {
  value       = var.replicas
  description = "Replica count asked for, which is what a Pending pod count is measured against"
}

output "deployment_status_command" {
  value       = "kubectl -n ${var.namespace} get deployment ${var.name} -o wide"
  description = "Command that shows how many of the requested replicas are ready"
}

output "pending_pods_command" {
  value       = "kubectl -n ${var.namespace} get pods -l app=${var.name} --field-selector status.phase=Pending -o wide"
  description = "Command that lists the pods that did not fit. On a single-node cluster this is the demonstration: kubectl describe on one of them says whether it was the pod ceiling or an address that ran out"
}

output "pod_distribution_command" {
  value       = "kubectl -n ${var.namespace} get pods -l app=${var.name} -o wide --sort-by=.spec.nodeName"
  description = "Command that shows which node each pod landed on, which is how the ASG variant's second node becomes visible"
}
