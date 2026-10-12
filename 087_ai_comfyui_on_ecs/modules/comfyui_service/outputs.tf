output "service_name" {
  value       = aws_ecs_service.comfyui.name
  description = "Name of the ECS service, which the admin functions read and update"
}
output "task_definition_arn" {
  value       = aws_ecs_task_definition.comfyui.arn
  description = "ARN of the task definition revision the service runs"
}
output "security_group_id" {
  value       = aws_security_group.service.id
  description = "Security group of the task's network interface"
}
output "log_group_name" {
  value       = aws_cloudwatch_log_group.comfyui.name
  description = "Log group ComfyUI writes to"
}
output "volume_name" {
  value       = var.volume_name
  description = "Name of the Docker volume, which REX-Ray also gives the EBS volume behind it as its Name tag - re-exposed so the volume can be found after destroy (rules.md B-5)"
}
output "service_events_command" {
  value       = "aws ecs describe-services --cluster ${var.cluster_arn} --services ${aws_ecs_service.comfyui.name} --query 'services[0].{Running:runningCount,Pending:pendingCount,Desired:desiredCount,Events:events[0:5].message}' --output json"
  description = "The service's task counts and its last five events - where a task that cannot be placed (no instance yet, no GPU free) or cannot start (image pull, volume) explains itself"
}
output "logs_command" {
  value       = "aws logs tail ${aws_cloudwatch_log_group.comfyui.name} --since 1h --follow"
  description = "ComfyUI's log, followed"
}
