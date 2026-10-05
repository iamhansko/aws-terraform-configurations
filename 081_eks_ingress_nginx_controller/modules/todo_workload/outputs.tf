output "name" {
  value       = var.name
  description = "Name of the Deployment and of the Ingress"
}
output "namespace" {
  value       = var.namespace
  description = "Namespace everything here lives in, re-exposed so the caller's diagnostic commands read one value (rules.md B-5)"
}
output "service_name" {
  value       = local.service_name
  description = "Name of the Service the Ingress points at, derived from name rather than taken as its own variable"
}
output "ingress_class_name" {
  value       = var.ingress_class_name
  description = "The IngressClass this Ingress asked for, re-exposed so a mismatch with the classes the controllers actually own is visible in terraform output rather than only as an Ingress that never gets an address (rules.md B-5)"
}
output "path_prefix" {
  value       = var.path_prefix
  description = "The prefix the app is served under, re-exposed so the caller builds its demo URL from the same value that reached uvicorn and the Ingress rule (rules.md B-5)"
}
output "docs_path" {
  value       = "${var.path_prefix}/docs"
  description = "Path to the app's OpenAPI page, which is the quickest thing to open in a browser to see whether the whole chain - load balancer, ingress controller, Ingress rule, rewrite, Service, app - is working"
}
output "rollout_status_command" {
  value       = "kubectl -n ${var.namespace} rollout status deployment ${var.name} --timeout=10m"
  description = "Waits for the pod. Long timeout on purpose: the claim provisions an EBS volume only once the pod is scheduled, MySQL initialises its data directory on first start, and the app container restarts until that finishes"
}
output "pod_status_command" {
  value       = "kubectl -n ${var.namespace} get pods -l app=${var.name}-app -o wide"
  description = "The pod and its three containers. READY 2/3 or 3/3 with restarts on the fastapi container is the expected picture while MySQL initialises; a pod stuck Pending is the claim rather than the app"
}
output "claim_status_command" {
  value       = "kubectl -n ${var.namespace} get pvc ${local.claim_name} -o wide"
  description = "The claim and the volume behind it. Pending with WaitForFirstConsumer is normal until the pod is scheduled; Pending after that means no provisioner answered, which points at the EBS CSI driver addon rather than at anything here"
}
output "ingress_status_command" {
  value       = "kubectl -n ${var.namespace} get ingress ${var.name} -o wide"
  description = "The Ingress, its class and the address its controller attached. An empty ADDRESS means no controller claimed it - check that the CLASS column names a class one of the controllers actually owns"
}
output "ingress_describe_command" {
  value       = "kubectl -n ${var.namespace} describe ingress ${var.name}"
  description = "The same object with the controller's events. This is where a rewrite or a path problem shows up, and where an Ingress naming an unowned class is conspicuous by having no events at all"
}
