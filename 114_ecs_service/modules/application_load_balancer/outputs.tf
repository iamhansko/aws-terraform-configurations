output "load_balancer_arn" {
  value       = aws_lb.load_balancer.arn
  description = "ARN of the ALB"
}
output "dns_name" {
  value       = aws_lb.load_balancer.dns_name
  description = "DNS name of the ALB"
}
output "url" {
  value       = "http://${aws_lb.load_balancer.dns_name}${var.listener_port == 80 ? "" : ":${var.listener_port}"}"
  description = "URL the service answers on"
}
output "security_group_id" {
  value       = aws_security_group.load_balancer.id
  description = "ID of the ALB's security group, for the service's security group to accept traffic from"
}
output "primary_target_group_arn" {
  value       = aws_lb_target_group.target_group["primary"].arn
  description = "ARN of the target group the service registers its tasks into"
}
output "alternate_target_group_arn" {
  value       = aws_lb_target_group.target_group["alternate"].arn
  description = "ARN of the alternate target group the service's advanced_configuration names"
}
output "production_listener_rule_arn" {
  value       = aws_lb_listener_rule.production.arn
  description = "ARN of the production listener rule. A service referencing this is ordered after the listener as well, since the rule depends on it - which is what ECS needs before it will register a task into the primary group"
}
output "target_port" {
  value       = var.target_port
  description = "Port the targets listen on (rules.md B-5)"
}
output "target_health_command" {
  value       = "aws elbv2 describe-target-health --target-group-arn ${aws_lb_target_group.target_group["primary"].arn} --query 'TargetHealthDescriptions[].[Target.Id,Target.AvailabilityZone,TargetHealth.State,TargetHealth.Reason]' --output table"
  description = "Whether the ALB can reach the tasks. Targets stuck in unhealthy with Target.Timeout is a security group path problem, not an application one"
}
