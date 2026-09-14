output "dns_name" {
  value       = aws_lb.application_load_balancer.dns_name
  description = "DNS name of the application load balancer"
}

output "security_group_id" {
  value       = aws_security_group.application_load_balancer_security_group.id
  description = "ID of the application load balancer's security group"
}

output "target_group_arn" {
  value       = aws_lb_target_group.target_group.arn
  description = "ARN of the target group, for the ASG module to attach instances to"
}
