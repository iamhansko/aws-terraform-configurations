output "service_name" {
  value       = aws_ecs_service.ecs_service.name
  description = "Name of the service. Taken from the resource so that reading it orders the reader after the service - the CodeDeploy deployment group needs that"
}
output "service_arn" {
  value       = aws_ecs_service.ecs_service.id
  description = "ARN of the service"
}
output "task_definition_arn" {
  value       = aws_ecs_task_definition.ecs_task_definition.arn
  description = "The revision this apply registered, revision number included. Only the first one - every revision after it is registered by CodeBuild and is not a Terraform resource"
}
output "task_definition_family" {
  value       = aws_ecs_task_definition.ecs_task_definition.family
  description = "Family the pipeline registers its revisions into, re-exposed so the buildspec and this module do not restate it (rules.md B-5)"
}
output "task_definition_revision" {
  value       = aws_ecs_task_definition.ecs_task_definition.revision
  description = "Revision number this apply registered. A running service on a higher revision is the normal state after a deployment, not drift"
}
output "container_name" {
  value       = var.container_name
  description = "Name of the container, re-exposed so the appspec the buildspec writes and the service's load_balancer block are built from one value (rules.md B-5)"
}
output "container_port" {
  value       = var.container_port
  description = "Port the container listens on, re-exposed for the same reason (rules.md B-5)"
}
output "execution_role_arn" {
  value       = aws_iam_role.ecs_task_execution_role.arn
  description = "ARN of the task execution role. The buildspec writes it into the task definition it registers, and the CodeBuild role's iam:PassRole is scoped to exactly this role (rules.md A-5)"
}
output "execution_role_name" {
  value       = aws_iam_role.ecs_task_execution_role.name
  description = "Generated name of the task execution role"
}
output "log_group_name" {
  value       = aws_cloudwatch_log_group.ecs_task_log_group.name
  description = "Name of the log group the container writes to"
}
output "log_group_arn" {
  value       = aws_cloudwatch_log_group.ecs_task_log_group.arn
  description = "ARN of that log group"
}
output "security_group_id" {
  value       = aws_security_group.ecs_service_security_group.id
  description = "ID of the task security group, the one that matters under awsvpc - the load balancer has to get past this to reach the container port, and the task's outbound calls leave through it"
}
output "service_status_command" {
  value       = "aws ecs describe-services --cluster ${var.cluster_name} --services ${aws_ecs_service.ecs_service.name} --query 'services[0].[status,desiredCount,runningCount,pendingCount,taskSets[].[id,status,stabilityStatus]]' --output json"
  description = "Command printing the service's task counts and its task sets. Two task sets means a deployment is in progress; one PRIMARY task set is the settled state"
}
output "service_events_command" {
  value       = "aws ecs describe-services --cluster ${var.cluster_name} --services ${aws_ecs_service.ecs_service.name} --query 'services[0].events[:10].[createdAt,message]' --output table"
  description = "The service's own account of what it has been trying to do. Nearly every failure here surfaces in this list rather than in Terraform: an unplaceable task is capacity, a repeating stopped-task message is the image or the egress rule"
}
output "stopped_task_reason_command" {
  value       = "aws ecs list-tasks --cluster ${var.cluster_name} --service-name ${aws_ecs_service.ecs_service.name} --desired-status STOPPED --query taskArns --output text | xargs -r aws ecs describe-tasks --cluster ${var.cluster_name} --tasks --query 'tasks[].[stoppedReason,containers[0].reason]' --output table"
  description = "Why stopped tasks stopped. CannotPullContainerError against an image that exists is the revoked task egress rule; a manifest-not-found reason means the seed image was never pushed"
}
output "container_log_command" {
  value       = "aws logs tail ${aws_cloudwatch_log_group.ecs_task_log_group.name} --since 10m --format short"
  description = "The container's output. Empty with tasks running means the awslogs driver cannot reach CloudWatch Logs, which is the same egress rule - and in that case the task would not have started at all, so empty with healthy tasks means nothing has been requested yet"
}
