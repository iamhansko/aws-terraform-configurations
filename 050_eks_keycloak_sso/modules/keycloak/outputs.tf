output "namespace" {
  value       = var.namespace
  description = "Namespace Keycloak runs in, re-exposed so callers do not restate it (rules.md B-5)"
}
output "hostname" {
  value       = var.hostname
  description = "Host the Ingress matches on, re-exposed so a mismatch with the certificate or the DNS record is visible in outputs (rules.md B-5)"
}
output "url" {
  value       = "https://${var.hostname}"
  description = "Keycloak URL. https because the ALB terminates TLS with the ACM certificate; the Ingress also redirects http to it"
}
output "stack_tag" {
  value       = "${var.namespace}/${var.ingress_name}"
  description = "The <namespace>/<name> value the AWS Load Balancer Controller writes into its ingress.k8s.aws/stack tag for this Ingress. A pre-created load balancer must carry exactly this to be adopted rather than duplicated (rules.md B-5/G-3)"
}
output "container_port" {
  value       = var.container_port
  description = "Port Keycloak serves on, which with target-type ip is where the load balancer sends traffic - so the port the pod-side rule opens (rules.md G-1/G-2)"
}
output "admin_username" {
  value       = var.admin_username
  description = "Bootstrap admin username. The password deliberately has no output (rules.md H-2)"
}
output "rollout_command" {
  value       = "kubectl -n ${var.namespace} rollout status statefulset ${var.service_name} --timeout=15m"
  description = "Command confirming Keycloak finished starting. Its startup probe allows ten minutes, so this is the thing to watch rather than reloading the URL"
}
output "pods_command" {
  value       = "kubectl -n ${var.namespace} get pods -o wide"
  description = "Command listing the Keycloak and PostgreSQL pods. Pods Pending here mean the node group could not fit them - two replicas request 1700Mi each"
}
output "ingress_command" {
  value       = "kubectl -n ${var.namespace} get ingress ${var.ingress_name} -o wide"
  description = "Command showing the Ingress and whether the controller gave it an address. An empty ADDRESS means no controller is reconciling it, usually a class mismatch (rules.md G-1)"
}
output "logs_command" {
  value       = "kubectl -n ${var.namespace} logs statefulset/${var.service_name} --tail 100"
  description = "Command reading Keycloak's log. Where a database it cannot reach, or a proxy header configuration that breaks its redirects, explains itself"
}
