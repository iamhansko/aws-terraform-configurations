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
  description = "URL the deployed application answers on"
}
output "security_group_id" {
  value       = aws_security_group.load_balancer_security_group.id
  description = "ID of the ALB's security group, which the service's security group accepts the container port from"
}
output "listener_arn" {
  value       = aws_lb_listener.listener.arn
  description = "ARN of the production listener. CodeDeploy's prod_traffic_route names it, and rewriting its default action is how a blue/green deployment shifts traffic"
}
output "blue_target_group_arn" {
  value       = aws_lb_target_group.target_group["blue"].arn
  description = "ARN of the blue target group"
}
output "blue_target_group_name" {
  value       = aws_lb_target_group.target_group["blue"].name
  description = "Name of the blue target group. CodeDeploy's target_group blocks take names rather than ARNs, so the deployment group reads it from here (rules.md B-5)"
}
output "green_target_group_arn" {
  value       = aws_lb_target_group.target_group["green"].arn
  description = "ARN of the green target group"
}
output "green_target_group_name" {
  value       = aws_lb_target_group.target_group["green"].name
  description = "Name of the green target group, for CodeDeploy's second target_group block (rules.md B-5)"
}
# The group the listener forwards to at creation, handed back so the caller passes the same one into the
# service's load_balancer block instead of choosing again (rules.md B-5). The service, the listener and
# CodeDeploy all have to agree on which half of the pair is live to begin with.
output "initial_target_group_arn" {
  value       = aws_lb_target_group.target_group[var.initial_target_group_key].arn
  description = "ARN of the target group the listener forwards to at creation, which is the group the ECS service registers its tasks into"
}
output "initial_target_group_key" {
  value       = var.initial_target_group_key
  description = "Which half of the pair is live at creation, re-exposed so the README can say so without the reader working it out (rules.md B-5)"
}
output "target_port" {
  value       = var.target_port
  description = "Port the targets listen on, re-exposed so the service's container port and the target groups cannot drift apart (rules.md B-5)"
}
output "health_check_path" {
  value       = var.health_check_path
  description = "Path both target groups health-check, re-exposed so the container health check in the task definition uses the same path (rules.md B-5)"
}
output "target_health_command" {
  value       = "for tg in ${aws_lb_target_group.target_group["blue"].arn} ${aws_lb_target_group.target_group["green"].arn}; do echo \"$tg\"; aws elbv2 describe-target-health --target-group-arn \"$tg\" --query 'TargetHealthDescriptions[].[Target.Id,Target.Port,TargetHealth.State,TargetHealth.Reason]' --output table; done"
  description = "Target health in both groups. Exactly one of them holds healthy targets between deployments; both do briefly during a cutover. Targets stuck unhealthy with Target.Timeout is a security group path problem rather than an application one"
}
output "live_target_group_command" {
  value       = "aws elbv2 describe-listeners --listener-arns ${aws_lb_listener.listener.arn} --query 'Listeners[0].DefaultActions[0].TargetGroupArn' --output text"
  description = "Which target group is live right now. This is the field CodeDeploy rewrites and Terraform deliberately stops tracking, so the listener itself is the only honest answer"
}
