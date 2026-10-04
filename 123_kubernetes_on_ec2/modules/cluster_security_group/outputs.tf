output "security_group_id" {
  value       = aws_security_group.cluster.id
  description = "ID of the shared cluster security group. Every instance in the cluster carries it, and the self-rule on it is what lets the control plane, the workers and the workbench talk to each other"
}

output "security_group_name" {
  value       = aws_security_group.cluster.name
  description = "Name of the shared cluster security group"
}
