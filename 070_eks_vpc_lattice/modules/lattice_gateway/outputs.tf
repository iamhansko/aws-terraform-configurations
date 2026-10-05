output "name" {
  value       = var.name
  description = "Name of the Gateway, which routes name in their parentRefs and which the controller pairs with the VPC Lattice service network of the same name"
}
output "namespace" {
  value       = var.namespace
  description = "Namespace the Gateway lives in, re-exposed so routes attach in the same namespace (rules.md B-5)"
}
output "listener_name" {
  value       = var.listener_name
  description = "Name of the listener, re-exposed because an HTTPRoute's sectionName has to match it - and a route naming a listener that does not exist is accepted and simply never attached (rules.md B-5)"
}
output "gateway_class_name" {
  value       = var.gateway_class_name
  description = "Name of the GatewayClass, re-exposed for diagnostics"
}
output "status_command" {
  value       = "kubectl -n ${var.namespace} get gateway ${var.name} -o wide"
  description = "The Gateway and the address the controller assigned it. An empty ADDRESS with PROGRAMMED False is the controller not having built the Lattice service network - its log says why, and the Gateway itself does not"
}
output "describe_command" {
  value       = "kubectl -n ${var.namespace} describe gateway ${var.name}"
  description = "The same object with its conditions and the controller's events. This is where a class naming the wrong controller shows up as no events at all, which is different from an event saying something failed"
}
