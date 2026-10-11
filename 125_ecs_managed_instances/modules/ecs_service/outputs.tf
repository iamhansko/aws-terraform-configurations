output "service_name" {
  value       = aws_ecs_service.service.name
  description = "Name of the ECS service"
}
output "service_arn" {
  value       = aws_ecs_service.service.id
  description = "ARN of the ECS service"
}
output "security_group_id" {
  value       = aws_security_group.service.id
  description = "ID of the tasks' own security group"
}
output "log_group_name" {
  value       = aws_cloudwatch_log_group.service.name
  description = "Log group the container writes to"
}
output "service_events_command" {
  value       = "aws ecs describe-services --cluster ${var.cluster_name} --services ${aws_ecs_service.service.name} --query 'services[0].events[:10].[createdAt,message]' --output table"
  description = "The service's own account of what it has been doing. A task that cannot be placed, pulled, mounted or health-checked is reported here first"
}
output "stopped_task_reason_command" {
  value       = "aws ecs list-tasks --cluster ${var.cluster_name} --service-name ${aws_ecs_service.service.name} --desired-status STOPPED --query taskArns --output text | xargs -r aws ecs describe-tasks --cluster ${var.cluster_name} --query 'tasks[].[stoppedReason,containers[0].reason]' --output table --tasks"
  description = "Why recent tasks stopped. ResourceInitializationError naming a secret or an EFS mount is the execution role or the NFS path"
}
output "log_tail_command" {
  value       = "aws logs tail ${aws_cloudwatch_log_group.service.name} --follow --since 10m"
  description = "The container's own output"
}
