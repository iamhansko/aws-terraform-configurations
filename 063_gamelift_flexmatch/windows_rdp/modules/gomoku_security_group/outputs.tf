output "security_group_id" {
  value       = aws_security_group.gomoku_default.id
  description = "ID of the group, attached to the ElastiCache node and the two VPC-attached Lambda functions"
}
output "security_group_name" {
  value       = aws_security_group.gomoku_default.name
  description = "Name of the group. A CloudShell VPC environment launched with this group is how redis_command in the root outputs reaches the node"
}
