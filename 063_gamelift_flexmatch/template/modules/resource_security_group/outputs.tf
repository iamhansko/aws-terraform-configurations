output "security_group_id" {
  value       = aws_security_group.resource_security_group.id
  description = "ID of the shared group, attached to the ElastiCache node and the VPC-attached Lambda functions"
}
