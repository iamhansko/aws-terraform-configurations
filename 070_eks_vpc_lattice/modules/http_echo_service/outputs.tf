output "name" {
  value       = var.name
  description = "Name of the Deployment and the Service, which is what an HTTPRoute's backendRef names"
}
output "namespace" {
  value       = var.namespace
  description = "Namespace the pair lives in, re-exposed so a route in the same namespace can name it without qualification (rules.md B-5)"
}
output "service_port" {
  value       = var.service_port
  description = "Port the Service publishes, re-exposed because a route's backendRef has to name this port - and one naming a port the Service does not publish leaves the route attached and answering 500 (rules.md B-5)"
}
output "pod_name_label" {
  value       = local.pod_name_label
  description = "The text this backend's responses carry, re-exposed so a caller describing the demo quotes what the server will actually say"
}
output "pods_command" {
  value       = "kubectl -n ${var.namespace} get pods -l app=${var.name} -o wide"
  description = "The pods behind this backend. Their addresses are what the controller registers in the VPC Lattice target group, so a pod that is not Running is a target that is not registered"
}
