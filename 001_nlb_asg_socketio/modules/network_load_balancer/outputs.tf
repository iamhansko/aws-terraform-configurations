output "dns_name" {
  value       = aws_lb.network_load_balancer.dns_name
  description = "DNS name of the network load balancer"
}

output "security_group_id" {
  value       = aws_security_group.network_load_balancer_security_group.id
  description = "ID of the network load balancer's security group"
}

output "target_group_arn" {
  value       = aws_lb_target_group.target_group.arn
  description = "ARN of the target group, for the ASG module to attach instances to"
}
