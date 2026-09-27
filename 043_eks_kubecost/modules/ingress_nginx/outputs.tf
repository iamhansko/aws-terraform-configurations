output "release_name" {
  value       = helm_release.ingress_nginx.name
  description = "Name of the Helm release"
}
output "namespace" {
  value       = var.namespace
  description = "Namespace the controller runs in, re-exposed so callers do not restate it (rules.md B-5)"
}
output "ingress_class_name" {
  value       = var.ingress_class_name
  description = "IngressClass this controller owns. An Ingress has to name this in spec.ingressClassName to be reconciled by this controller rather than one of the others"
}
output "service_name" {
  value       = var.service_name
  description = "Name of the controller Service the chart creates, re-exposed from the input (rules.md B-5)"
}
output "stack_tag" {
  value       = var.stack_tag
  description = "The service.k8s.aws/stack value this Service's load balancer must carry to be adopted. Re-exposed so it can be compared against the pre-created load balancer's tag in terraform output (rules.md B-5/G-3)"
}
output "load_balancer_hostname_command" {
  value       = "kubectl -n ${var.namespace} get service ${var.service_name} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
  description = "Command reading the address the controller actually attached. Worth comparing against the pre-created load balancer's DNS name: if they differ, adoption failed and there are now two load balancers (rules.md G-3)"
}
