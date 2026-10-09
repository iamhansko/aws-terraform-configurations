output "service_name" {
  value       = aws_ecs_service.service.name
  description = "Name of the ECS service. The CodeDeploy deployment group and the workflow's deploy action both name it, so both read it from here (rules.md B-5)"
}
output "service_arn" {
  value       = aws_ecs_service.service.id
  description = "ARN of the ECS service, which the provider reports as its id"
}
output "task_definition_arn" {
  value       = aws_ecs_task_definition.task_definition.arn
  description = "ARN of the revision Terraform created. Only the first one: every deployment registers a new revision that Terraform deliberately stops tracking, so this is the starting point rather than what is running"
}
output "task_family" {
  value       = aws_ecs_task_definition.task_definition.family
  description = "Task definition family. The association that seeds the repository exports this family into taskdef.json, so the export and the definition name one family (rules.md B-5)"
}
output "container_name" {
  value       = var.container_name
  description = "Name of the container, re-exposed because the appspec's LoadBalancerInfo and the workflow's render step both have to use the same name as the service's load_balancer block (rules.md B-5)"
}
output "container_port" {
  value       = var.container_port
  description = "Port the container listens on, re-exposed for the appspec's LoadBalancerInfo (rules.md B-5)"
}
output "security_group_id" {
  value       = aws_security_group.service_security_group.id
  description = "ID of the tasks' security group"
}
output "task_role_arn" {
  value       = aws_iam_role.task.arn
  description = "ARN of the task role, so a caller granting a pipeline iam:PassRole can scope it to the roles a task definition in this project may name"
}
output "task_execution_role_arn" {
  value       = aws_iam_role.task_execution.arn
  description = "ARN of the task execution role, for the same reason as task_role_arn"
}
output "service_status_command" {
  value       = "aws ecs describe-services --cluster ${var.cluster_name} --services ${aws_ecs_service.service.name} --query 'services[0].[status,launchType,desiredCount,runningCount,pendingCount,taskSets[].[id,status,stabilityStatus]]' --output json"
  description = "Desired against running tasks, and the task sets. Two task sets with one PRIMARY and one ACTIVE is a cutover in progress; a task set left behind afterwards is a deployment that was stopped rather than completed"
}
output "service_events_command" {
  value       = "aws ecs describe-services --cluster ${var.cluster_name} --services ${aws_ecs_service.service.name} --query 'services[0].events[:10].[createdAt,message]' --output table"
  description = "Where a pull failure, an unhealthy target or a task that could not be placed is reported first. \"unable to place a task because no container instance met all of its requirements\" during a cutover is the capacity provider's ceiling rather than a placement constraint"
}
output "list_task_definitions_command" {
  value       = "aws ecs list-task-definitions --family-prefix ${aws_ecs_task_definition.task_definition.family} --sort DESC --query taskDefinitionArns --output table"
  description = "Every revision of the family, newest first. Revision 1 is Terraform's; each later one was registered by a workflow run, which is why this configuration stops tracking the field that names the live one"
}
