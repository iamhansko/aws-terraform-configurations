output "security_group_id" {
  value       = aws_security_group.load_balancer_security_group.id
  description = "ID of the load balancer's frontend security group, for the Ingress or Service annotation that hands it to the AWS Load Balancer Controller"
}
output "security_group_name" {
  value       = aws_security_group.load_balancer_security_group.name
  description = "Name of the load balancer's frontend security group"
}
output "port" {
  value       = var.port
  description = "Listener port opened on the group, re-exposed so the workload's Service port references one source of truth (rules.md #5)"
}
