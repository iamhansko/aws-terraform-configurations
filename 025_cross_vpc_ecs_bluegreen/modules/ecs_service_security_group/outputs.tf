output "security_group_id" {
  value       = aws_security_group.ecs_service_security_group.id
  description = "The group each task's elastic network interface gets. Both application stacks attach it, and the Aurora group names it as an allowed source"
}
output "security_group_name" {
  value       = aws_security_group.ecs_service_security_group.name
  description = "Name of the group"
}
output "container_port" {
  value       = var.container_port
  description = "Port opened to each source group, re-exposed from the input so a stack's container port and this group's rules come from one value (rules.md B-5). Nothing checks that a task definition's port matches a rule: a mismatch leaves every target unhealthy with no error"
}
