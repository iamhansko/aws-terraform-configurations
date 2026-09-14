output "security_group_id" {
  value       = aws_security_group.auto_scaling_group_security_group.id
  description = "ID of the ASG instances' security group"
}

output "auto_scaling_group_name" {
  value       = aws_autoscaling_group.auto_scaling_group.name
  description = "Name of the auto scaling group"
}
