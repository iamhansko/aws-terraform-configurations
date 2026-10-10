output "service_name" {
  value       = aws_ecs_service.ecs_service.name
  description = "Name of the service"
}
output "service_id" {
  value       = aws_ecs_service.ecs_service.id
  description = "ID of the service, which for this resource is its ARN"
}
output "task_definition_arn" {
  value       = aws_ecs_task_definition.ecs_task_definition.arn
  description = "ARN of the task definition revision the service is running, including the revision number"
}
output "task_definition_family" {
  value       = aws_ecs_task_definition.ecs_task_definition.family
  description = "Task definition family"
}
output "task_role_arn" {
  value       = aws_iam_role.ecs_task_role.arn
  description = "ARN of the task role, assumed by the process inside the container and by an ECS Exec session"
}
output "task_role_name" {
  value       = aws_iam_role.ecs_task_role.name
  description = "Generated name of the task role, for attaching further policies from the root"
}
output "task_execution_role_arn" {
  value       = aws_iam_role.ecs_task_execution_role.arn
  description = "ARN of the task execution role, assumed by the ECS agent to pull the image and open the log stream"
}
output "log_group_name" {
  value       = aws_cloudwatch_log_group.ecs_task_log_group.name
  description = "CloudWatch log group the container and its ECS Exec sessions write to"
}
# Inputs handed back out so the root builds its commands from the values in effect rather than keeping its
# own copy of them (rules.md B-5). container_name is the one an execute-command has to name exactly.
output "container_name" {
  value       = var.container_name
  description = "Name of the container in the task, which is what aws ecs execute-command --container takes"
}
output "container_port" {
  value       = var.container_port
  description = "Port the container listens on, or null"
}
output "enable_execute_command" {
  value       = var.enable_execute_command
  description = "Whether ECS Exec is enabled on the service"
}
output "service_connect_client_alias" {
  value       = try(var.service_connect.server == null, true) ? null : "${var.service_connect.server.client_alias_dns_name}:${var.service_connect.server.client_alias_port}"
  description = "host:port other Service Connect clients in the namespace reach this service at, or null when the service publishes no endpoint"
}
# Terraform cannot know which tasks are running - ECS decides that after apply returns - so these are
# commands rather than values.
output "first_task_arn_command" {
  value       = "aws ecs list-tasks --cluster ${var.cluster_name} --service-name ${aws_ecs_service.ecs_service.name} --desired-status RUNNING --query 'taskArns[0]' --output text"
  description = "Prints the ARN of one running task. ECS Exec takes a task ARN or ID; the root composes execute-command around this"
}
output "service_status_command" {
  value       = "aws ecs describe-services --cluster ${var.cluster_name} --services ${aws_ecs_service.ecs_service.name} --query 'services[0].[status,desiredCount,runningCount,pendingCount,deployments[0].rolloutState,deployments[0].rolloutStateReason]' --output json"
  description = "Desired against running counts and the rollout state. runningCount below desiredCount for more than a few minutes is the signal to read service_events_command"
}
output "service_events_command" {
  value       = "aws ecs describe-services --cluster ${var.cluster_name} --services ${aws_ecs_service.ecs_service.name} --query 'services[0].events[:10].[createdAt,message]' --output table"
  description = "The service's own account of what it has been trying to do. Nearly every failure ends up here rather than anywhere in Terraform"
}
output "stopped_task_reason_command" {
  value       = "aws ecs list-tasks --cluster ${var.cluster_name} --service-name ${aws_ecs_service.ecs_service.name} --desired-status STOPPED --query taskArns --output text | xargs -r aws ecs describe-tasks --cluster ${var.cluster_name} --query 'tasks[].[stoppedReason,containers[0].reason]' --output table --tasks"
  description = "Why the stopped tasks stopped. --tasks is last so that the ARNs xargs appends become its values"
}
output "execute_command_agent_command" {
  value       = "aws ecs list-tasks --cluster ${var.cluster_name} --service-name ${aws_ecs_service.ecs_service.name} --desired-status RUNNING --query taskArns --output text | xargs -r aws ecs describe-tasks --cluster ${var.cluster_name} --query 'tasks[].[taskArn,lastStatus,enableExecuteCommand,containers[0].managedAgents[0].lastStatus]' --output table --tasks"
  description = "Whether each running task can take an ECS Exec session: enableExecuteCommand True and the ExecuteCommandAgent RUNNING. A task started before exec was enabled shows False and needs replacing"
}
output "container_log_command" {
  value       = "aws logs tail ${aws_cloudwatch_log_group.ecs_task_log_group.name} --follow --since 30m"
  description = "The container output and the ECS Exec session logs, as they arrive"
}
