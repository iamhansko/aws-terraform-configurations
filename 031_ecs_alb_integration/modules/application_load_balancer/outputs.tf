output "load_balancer_arn" {
  value       = aws_lb.load_balancer.arn
  description = "ARN of the load balancer"
}
# The dimension value every AWS/ApplicationELB metric is published against. The dashboard and the alarm both
# need it, and taking it from here rather than parsing the ARN is what keeps them pointed at this load
# balancer (rules.md B-5).
output "arn_suffix" {
  value       = aws_lb.load_balancer.arn_suffix
  description = "app/<name>/<id> portion of the ARN, which is the LoadBalancer dimension of its CloudWatch metrics"
}
output "dns_name" {
  value       = aws_lb.load_balancer.dns_name
  description = "DNS name of the load balancer"
}
output "url" {
  value       = "http://${aws_lb.load_balancer.dns_name}${var.listener_port == 80 ? "" : ":${var.listener_port}"}"
  description = "URL the service answers on"
}
output "security_group_id" {
  value       = aws_security_group.load_balancer.id
  description = "ID of the load balancer's security group, for the tasks' security group to accept traffic from (rules.md B-6)"
}
output "target_group_arn" {
  value       = aws_lb_target_group.target_group.arn
  description = "ARN of the target group the ECS service registers its tasks into"
}
output "listener_arn" {
  value       = aws_lb_listener.listener.arn
  description = "ARN of the listener"
}
output "target_port" {
  value       = var.target_port
  description = "Port the targets listen on, handed back out so the service's container port and this one are one value (rules.md B-5)"
}
output "target_health_command" {
  value       = "aws elbv2 describe-target-health --target-group-arn ${aws_lb_target_group.target_group.arn} --query 'TargetHealthDescriptions[].[Target.Id,Target.Port,TargetHealth.State,TargetHealth.Reason]' --output table"
  description = "Whether the load balancer can reach the tasks. An empty table means ECS has not registered anything; Target.Timeout is a security group path problem rather than an application one"
}
