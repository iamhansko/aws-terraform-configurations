output "load_balancer_arn" {
  value       = aws_lb.load_balancer.arn
  description = "ARN of the load balancer"
}
output "load_balancer_name" {
  value       = aws_lb.load_balancer.name
  description = "Name of the load balancer"
}
output "dns_name" {
  value       = aws_lb.load_balancer.dns_name
  description = "DNS name of the load balancer"
}
output "zone_id" {
  value       = aws_lb.load_balancer.zone_id
  description = "Hosted zone of the load balancer, for a Route 53 alias record"
}
output "arn_suffix" {
  value       = aws_lb.load_balancer.arn_suffix
  description = "The load_balancer dimension CloudWatch uses for this load balancer's metrics"
}
output "url" {
  value       = "http://${aws_lb.load_balancer.dns_name}"
  description = "Base URL of the load balancer"
}
output "listener_arn" {
  value       = aws_lb_listener.listener.arn
  description = "ARN of the production listener. This is what the CodeDeploy deployment group takes as its prod_traffic_route, and its default rule is the field a deployment rewrites"
}
output "listener_port" {
  value       = var.listener_port
  description = "Port the listener accepts on, re-exposed so the caller does not restate it when opening a path to the tasks (rules.md B-5)"
}
output "security_group_id" {
  value       = aws_security_group.load_balancer_security_group.id
  description = "ID of the load balancer's security group. The task security group names this as the allowed source on the container port"
}
output "blue_target_group_arn" {
  value       = aws_lb_target_group.blue.arn
  description = "ARN of the target group production starts on. The ECS service's load_balancer block names this one, and CodeDeploy takes it over from there"
}
output "blue_target_group_name" {
  value       = aws_lb_target_group.blue.name
  description = "Name of the blue target group. CodeDeploy's load_balancer_info takes target groups by name rather than by ARN"
}
output "green_target_group_arn" {
  value       = aws_lb_target_group.green.arn
  description = "ARN of the target group a replacement task set registers into"
}
output "green_target_group_name" {
  value       = aws_lb_target_group.green.name
  description = "Name of the green target group"
}
output "target_port" {
  value       = var.target_port
  description = "Port the targets are registered on, re-exposed so the task definition's container port and the security group rule reaching it stay one value (rules.md B-5)"
}
output "health_check_path" {
  value       = var.health_check_path
  description = "Path the target groups health check, re-exposed so the container's own health check command and the Go application's route can be built from the same value (rules.md B-5)"
}
output "listener_rules_command" {
  value       = "aws elbv2 describe-rules --listener-arn ${aws_lb_listener.listener.arn} --query 'Rules[].[Priority,Conditions[].Field|[0],Actions[0].TargetGroupArn]' --output table"
  description = "Command printing every rule on the listener with the target group it forwards to. This is where a blue/green switch is visible: every rule moves between the two target groups together, and one left behind on the other group blocks the next deployment"
}
output "target_health_command" {
  value       = "for tg in ${aws_lb_target_group.blue.arn} ${aws_lb_target_group.green.arn}; do aws elbv2 describe-target-health --target-group-arn $tg --query 'TargetHealthDescriptions[].[Target.Id,Target.Port,TargetHealth.State,TargetHealth.Reason]' --output table; done"
  description = "Command printing registered targets and their health in both target groups. Between deployments one holds the task addresses and the other is empty; all targets unhealthy with the tasks running is the signature of a missing security group rule rather than a broken application"
}
