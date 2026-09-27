output "security_group_id" {
  value       = aws_security_group.pod_security_group.id
  description = "ID of the pod security group. Goes into every ENIConfig's securityGroups list, and is the source the cluster security group has to accept traffic from - that reverse rule belongs to the caller, because it modifies a group this module does not own (rules.md C-1)"
}
output "security_group_name" {
  value       = aws_security_group.pod_security_group.name
  description = "Name of the pod security group"
}
output "webhook_port" {
  value       = var.webhook_port
  description = "Port the webhook rule opens, re-exposed so a caller's notes do not restate it (rules.md B-5)"
}
