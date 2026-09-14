output "security_group_id" {
  value       = aws_security_group.node_security_group.id
  description = "ID of the shared node security group, for the cluster's vpc_config and the node groups' launch templates"
}
output "security_group_name" {
  value       = aws_security_group.node_security_group.name
  description = "Name of the shared node security group"
}
