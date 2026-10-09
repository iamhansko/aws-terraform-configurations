output "service_name" {
  value       = aws_ecs_service.service.name
  description = "Name of the ECS service"
}
output "task_definition_arn" {
  value       = aws_ecs_task_definition.task_definition.arn
  description = "Task definition revision this apply registered"
}
output "container_name" {
  value       = var.container_name
  description = "Name of the container, handed back out so a caller building a dashboard widget or a log query does not restate it (rules.md B-5)"
}
output "security_group_id" {
  value       = aws_security_group.service.id
  description = "ID of the tasks' security group"
}
output "log_group_name" {
  value       = aws_cloudwatch_log_group.task.name
  description = "Group the container writes to, read off the resource so a caller's tail command names what was actually created (rules.md B-5)"
}
output "service_status_command" {
  value       = "aws ecs describe-services --cluster ${var.cluster_name} --services ${aws_ecs_service.service.name} --query 'services[0].[status,desiredCount,runningCount,deployments[0].rolloutState]' --output table"
  description = "Desired against running task counts and the rollout state"
}
output "service_events_command" {
  value       = "aws ecs describe-services --cluster ${var.cluster_name} --services ${aws_ecs_service.service.name} --query 'services[0].events[:10].[createdAt,message]' --output table"
  description = "The service's own account of what it has been doing. A pull failure or an unhealthy target is reported here before anywhere else"
}
output "tail_logs_command" {
  value       = "aws logs tail ${aws_cloudwatch_log_group.task.name} --follow --since 10m"
  description = "The container's stdout. The _monolithic template's task had no log configuration at all, so this is the view it did not have"
}
output "force_redeploy_command" {
  value       = "aws ecs update-service --cluster ${var.cluster_name} --service ${aws_ecs_service.service.name} --force-new-deployment"
  description = "Restarts the tasks against whatever is behind the image tag now. This is the second half of rebuilding the image by hand: the task definition names a moving tag, so a new push changes nothing until the tasks are replaced"
}
