output "name" {
  value       = var.name
  description = "Name of the HTTPRoute, which also ends up in the VPC Lattice service the controller creates for it"
}
output "namespace" {
  value       = var.namespace
  description = "Namespace the route lives in, re-exposed so the caller's diagnostic commands read one value (rules.md B-5)"
}
output "backend_names" {
  value       = distinct(flatten([for rule in var.rules : [for backend in rule.backends : backend.name]]))
  description = "Every Service this route sends traffic to, re-exposed so a caller can see at a glance which backends a route depends on - a backend that does not exist leaves the route attached and answering 500 (rules.md B-5)"
}
output "domain_name_command" {
  value       = "kubectl -n ${var.namespace} get httproute ${var.name} -o jsonpath='{.metadata.annotations.application-networking\\.k8s\\.aws/lattice-assigned-domain-name}'"
  description = "The address VPC Lattice assigned this route. The controller writes it back as an annotation once it has built the Lattice service, so it is empty until then - and there is no way to know it at apply time, which is why this is a command rather than a value"
}
output "status_command" {
  value       = "kubectl -n ${var.namespace} get httproute ${var.name} -o wide"
  description = "Whether the route attached to its Gateway. An empty parent list is a route the Gateway's listener did not allow or a sectionName that names nothing, and both are reported only in the route's own status"
}
output "describe_command" {
  value       = "kubectl -n ${var.namespace} describe httproute ${var.name}"
  description = "The route's conditions and the controller's events. ResolvedRefs False names the backend it could not find, which is the failure that otherwise shows up as a 500 from a route that looks healthy"
}
output "curl_command" {
  value       = "kubectl -n ${var.namespace} run curl-${var.name} --rm -it --restart=Never --image public.ecr.aws/docker/library/curl:8.16.0 -- curl -sS http://$(kubectl -n ${var.namespace} get httproute ${var.name} -o jsonpath='{.metadata.annotations.application-networking\\.k8s\\.aws/lattice-assigned-domain-name}')"
  description = "Calls the route from inside the cluster, which is the only place it can be called from: a VPC Lattice service is reachable from VPCs associated with its service network, and the association the controller makes is for the cluster's VPC. Run it repeatedly to see the responses name different pods"
}
