output "namespace" {
  value       = var.namespace
  description = "Namespace Kiali runs in, re-exposed so the root's commands read one value (rules.md B-5)"
}
output "name" {
  value       = var.name
  description = "Name of the Kiali CR, Deployment, Service and Ingress"
}
output "web_root" {
  value       = var.web_root
  description = "Path prefix Kiali serves under. The same value is the Ingress path and the load balancer health check path, so all three cannot disagree (rules.md B-5)"
}
output "server_port" {
  value       = var.server_port
  description = "Port the Kiali pod listens on. With target type ip this is what the pod-side security group rule has to open, not a Service port (rules.md G-2)"
}
output "ingress_stack_tag" {
  value       = "${var.namespace}/${var.name}"
  description = "The <namespace>/<name> value the AWS Load Balancer Controller writes into its ingress.k8s.aws/stack tag. A pre-created load balancer must carry exactly this to be adopted rather than duplicated, so it is derived here instead of being restated by the caller (rules.md B-5/G-3)"
}
output "load_balancer_hostname_command" {
  value       = "kubectl -n ${var.namespace} get ingress ${var.name} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
  description = "The address the controller attached to the Ingress. Compare it against the pre-created load balancer's URL: a different value means a second load balancer was built rather than the pre-created one adopted (rules.md G-3)"
}
output "server_status_command" {
  value       = "kubectl -n ${var.namespace} get kiali ${var.name} -o jsonpath='{.status.conditions}' ; echo ; kubectl -n ${var.namespace} get deployment ${var.name}"
  description = "What the operator made of the CR, then whether the server it built is up. The operator reconciles asynchronously after the Helm release finishes, so an empty Deployment here shortly after apply is normal rather than a failure"
}
output "operator_log_command" {
  value       = "kubectl -n ${var.namespace} logs deploy/kiali-operator --tail 100"
  description = "Where a rejected CR shows up. The operator validates the CR against its schema and reports there; the Helm release itself succeeds regardless, because it only had to create the resource"
}
