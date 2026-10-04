output "security_group_id" {
  value       = aws_security_group.ingress_security_group.id
  description = "ID of the public ingress security group, attached to the worker node that carries the Traefik hostPorts"
}
output "security_group_name" {
  value       = aws_security_group.ingress_security_group.name
  description = "Name of the load balancer's frontend security group"
}
output "ports" {
  value       = var.ports
  description = "Listener ports opened on the group, re-exposed so the workload's Service ports reference one source of truth (rules.md B-5)"
}
