output "security_group_id" {
  value       = aws_security_group.task_security_group.id
  description = "ID of the task security group, for the services' network_configuration"
}
output "self_ingress_ports" {
  value       = var.self_ingress_ports
  description = "Ports open between members of the group, handed back so the root reports the ports actually open rather than its own copy of them (rules.md B-5)"
}
