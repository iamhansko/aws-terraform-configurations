output "load_balancer_arn" {
  value       = aws_lb.load_balancer.arn
  description = "ARN of the load balancer. The app instance's ARN is what the root registers as the single target of the other instance's target group"
}
output "load_balancer_arn_suffix" {
  value       = aws_lb.load_balancer.arn_suffix
  description = "The net/<name>/<id> suffix. Also the description EC2 gives this load balancer's network interfaces, prefixed with \"ELB \" - which is how the workbench finds the app load balancer's private addresses to register them in the hub target group"
}
output "dns_name" {
  value       = aws_lb.load_balancer.dns_name
  description = "DNS name of the load balancer"
}
output "url" {
  value       = "http://${aws_lb.load_balancer.dns_name}"
  description = "HTTP URL of the load balancer. Only meaningful for the internet-facing instance; the internal one resolves to private addresses"
}
output "target_group_arn" {
  value       = aws_lb_target_group.load_balancer_target_group.arn
  description = "ARN of the target group the listener forwards to"
}
output "target_group_name" {
  value       = aws_lb_target_group.load_balancer_target_group.name
  description = "Name of the target group"
}
output "security_group_id" {
  value       = aws_security_group.load_balancer_security_group.id
  description = "The load balancer security group, named as an allowed source by whatever sits behind it (rules.md B-6)"
}
output "target_health_command" {
  value       = "aws elbv2 describe-target-health --target-group-arn ${aws_lb_target_group.load_balancer_target_group.arn} --query 'TargetHealthDescriptions[].[Target.Id,TargetHealth.State,TargetHealth.Reason]' --output table"
  description = "Command printing this target group's registered targets and their health. For the hub load balancer this is also how to tell whether the workbench registration step ran at all - an empty table means it did not"
}
