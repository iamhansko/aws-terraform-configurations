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
  description = "Name of the container, re-exposed for the execute-command line (rules.md B-5)"
}
output "security_group_id" {
  value       = aws_security_group.service.id
  description = "ID of the tasks' security group"
}
output "task_role_arn" {
  value       = aws_iam_role.task.arn
  description = "ARN of the role the containers and ECS Exec sessions run as"
}
output "service_status_command" {
  value       = "aws ecs describe-services --cluster ${var.cluster_name} --services ${aws_ecs_service.service.name} --query 'services[0].[status,desiredCount,runningCount,deployments[0].rolloutState]' --output table"
  description = "Desired against running task counts and the rollout state"
}
output "service_events_command" {
  value       = "aws ecs describe-services --cluster ${var.cluster_name} --services ${aws_ecs_service.service.name} --query 'services[0].events[:10].[createdAt,message]' --output table"
  description = "The service's own account of what it has been doing. A pull failure, an unhealthy target or a circuit-breaker rollback shows up here before anywhere else"
}
output "execute_command" {
  value       = "aws ecs execute-command --cluster ${var.cluster_name} --task $(aws ecs list-tasks --cluster ${var.cluster_name} --service-name ${aws_ecs_service.service.name} --query 'taskArns[0]' --output text) --container ${var.container_name} --interactive --command /bin/sh"
  description = "A shell inside one running task, through ECS Exec. Needs the Session Manager plugin on the machine it is run from"
}
