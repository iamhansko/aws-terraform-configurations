output "security_group_id" {
  value       = aws_security_group.cluster.id
  description = "ID of the shared security group. Every cluster's vpc_config, every node group and the bastion receive this one ID, which is what makes them mutually reachable (rules.md B-6)"
}
output "security_group_arn" {
  value       = aws_security_group.cluster.arn
  description = "ARN of the shared security group"
}
output "name" {
  value       = aws_security_group.cluster.name
  description = "Name of the shared security group"
}
