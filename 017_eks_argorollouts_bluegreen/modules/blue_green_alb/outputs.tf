output "arn" {
  value       = aws_lb.alb.arn
  description = "ARN of the load balancer"
}
output "dns_name" {
  value       = aws_lb.alb.dns_name
  description = "DNS name of the load balancer. Internal, so it only resolves usefully from inside the VPC - the bastion is where to curl it"
}
output "url" {
  value       = "http://${aws_lb.alb.dns_name}"
  description = "HTTP URL of the load balancer, known from state because Terraform created it rather than a controller (contrast rules.md G-1)"
}
output "target_group_arn" {
  value       = aws_lb_target_group.active.arn
  description = "ARN of the active target group. This is the value the Rollout's blue/green strategy names - the _monolithic template sed-substituted it into a YAML file, and it is interpolated into a kubectl_manifest instead (rules.md B-5)"
}
output "target_group_name" {
  value       = aws_lb_target_group.active.name
  description = "Name of the active target group"
}
output "listener_arn" {
  value       = aws_lb_listener.http.arn
  description = "ARN of the HTTP listener Argo Rollouts rewrites during a promotion"
}
output "target_health_command" {
  value       = "aws elbv2 describe-target-health --target-group-arn ${aws_lb_target_group.active.arn} --query 'TargetHealthDescriptions[].{Target:Target.Id,Port:Target.Port,State:TargetHealth.State}' --output table"
  description = "Command listing which pod IPs are registered and healthy. This is where a blue/green promotion is visible from the AWS side rather than from kubectl (rules.md H-2)"
}
