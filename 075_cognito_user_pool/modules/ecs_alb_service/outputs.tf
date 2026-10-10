output "load_balancer_dns_name" {
  value       = aws_lb.load_balancer.dns_name
  description = "DNS name of the load balancer"
}
output "url" {
  value       = "http://${aws_lb.load_balancer.dns_name}${var.listener_port == 80 ? "" : ":${var.listener_port}"}"
  description = "URL of the load balancer. Reachable only from what its security group admits"
}
output "service_name" {
  value       = aws_ecs_service.service.name
  description = "Name of the ECS service"
}
output "log_group_name" {
  value       = aws_cloudwatch_log_group.service.name
  description = "Log group the container writes to"
}
output "service_events_command" {
  value       = "aws ecs describe-services --cluster ${var.cluster_name} --services ${aws_ecs_service.service.name} --query 'services[0].events[:10].[createdAt,message]' --output table"
  description = "The service's own account of what it has been doing. A task that cannot pull, start or pass its health check is reported here first"
}
output "target_health_command" {
  value       = "aws elbv2 describe-target-health --target-group-arn ${aws_lb_target_group.service.arn} --query 'TargetHealthDescriptions[].[Target.Id,TargetHealth.State,TargetHealth.Reason]' --output table"
  description = "Whether the load balancer can reach the tasks"
}
output "log_tail_command" {
  value       = "aws logs tail ${aws_cloudwatch_log_group.service.name} --follow --since 10m"
  description = "The container's output"
}
