output "name" {
  value       = var.name
  description = "Name of the Ingress (rules.md B-5)"
}
output "load_balancer_hostname_command" {
  value       = "kubectl -n ${var.namespace} get ingress ${var.name} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' ; echo"
  description = "Reads the ALB address the controller attached. The load balancer is not a Terraform resource here, so the cluster is the only place the address exists (rules.md G-1)"
}
