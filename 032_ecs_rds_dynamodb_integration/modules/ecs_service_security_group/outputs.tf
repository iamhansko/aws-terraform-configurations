output "security_group_id" {
  value       = aws_security_group.ecs_service_security_group.id
  description = "ID of the group. Every task ENI is attached to it, and the database's ingress rule names it as a source - which is the edge the _monolithic template was missing, because its database rule named the VPC default group instead"
}
output "security_group_name" {
  value       = aws_security_group.ecs_service_security_group.name
  description = "Name of the group"
}
output "port" {
  value       = var.port
  description = "The application port, handed back out so the caller's task definitions, health checks and curl commands read one value (rules.md B-5)"
}
