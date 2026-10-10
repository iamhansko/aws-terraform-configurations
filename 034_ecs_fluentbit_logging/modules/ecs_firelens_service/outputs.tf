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
  description = "ARN of the task definition revision the service is running, including the revision number - the value to compare against what describe-services reports when a deployment appears to have done nothing"
}
output "task_definition_family" {
  value       = aws_ecs_task_definition.ecs_task_definition.family
  description = "Task definition family"
}
output "task_definition_revision" {
  value       = aws_ecs_task_definition.ecs_task_definition.revision
  description = "Revision number registered by this apply. It increments on every apply that changes the definition; old revisions stay registered and are not cleaned up"
}
output "task_role_arn" {
  value       = aws_iam_role.ecs_task_role.arn
  description = "ARN of the task role, which is the role Fluent Bit signs its PutLogEvents calls with"
}
output "task_execution_role_arn" {
  value       = aws_iam_role.ecs_task_execution_role.arn
  description = "ARN of the task execution role, which is the role the ECS agent pulls the images and opens the log router's own log stream with"
}
output "application_container_name" {
  value       = var.application_container_name
  description = "Name of the application container, handed back out because FireLens builds the record tag from it and the delivered stream names therefore contain it (rules.md B-5)"
}
output "log_router_container_name" {
  value       = var.log_router_container_name
  description = "Name of the log router container, handed back out so a caller's docker or kubectl-style command names the same container the task definition declared (rules.md B-5)"
}
# Terraform cannot know which tasks are running, where they landed, or whether a record was delivered -
# ECS decides all of that after apply returns. So these are commands.
output "service_status_command" {
  value       = "aws ecs describe-services --cluster ${var.cluster_name} --services ${aws_ecs_service.ecs_service.name} --query 'services[0].[status,desiredCount,runningCount,pendingCount,deployments[0].rolloutState,deployments[0].rolloutStateReason]' --output json"
  description = "Desired against running counts and the rollout state. runningCount below desiredCount with the rollout state at IN_PROGRESS for more than a few minutes is the signal to read the service events"
}
output "service_events_command" {
  value       = "aws ecs describe-services --cluster ${var.cluster_name} --services ${aws_ecs_service.ecs_service.name} --query 'services[0].events[:10].[createdAt,message]' --output table"
  description = "The service's own account of what it has been trying to do. Most failures in this project land here rather than anywhere in Terraform: no instance meeting the task's requirements means capacity, a missing logging driver capability or memory, and a repeating stopped-task message means the images"
}
output "stopped_task_reason_command" {
  value       = "aws ecs list-tasks --cluster ${var.cluster_name} --service-name ${aws_ecs_service.ecs_service.name} --desired-status STOPPED --query taskArns --output text | xargs -r aws ecs describe-tasks --cluster ${var.cluster_name} --tasks --query 'tasks[].[stoppedReason,containers[].[name,reason]]' --output json"
  description = "Why the stopped tasks stopped, per container. CannotPullContainerError means the build never pushed; a failure naming the logging driver on the log router means the awslogs group or its permission; and because both containers are essential, either one stopping takes the task with it"
}
output "running_task_placement_command" {
  value       = "aws ecs list-tasks --cluster ${var.cluster_name} --service-name ${aws_ecs_service.ecs_service.name} --desired-status RUNNING --query taskArns --output text | xargs -r aws ecs describe-tasks --cluster ${var.cluster_name} --tasks --query 'tasks[].[lastStatus,availabilityZone,containerInstanceArn]' --output table"
  description = "Where the running tasks ended up. Two task ARNs here is what makes the per-task metadata in the delivered records meaningful - each one has its own Fluent Bit sidecar and its own log stream"
}
output "describe_task_definition_command" {
  value       = "aws ecs describe-task-definition --task-definition ${aws_ecs_task_definition.ecs_task_definition.family}:${aws_ecs_task_definition.ecs_task_definition.revision} --query 'taskDefinition.containerDefinitions[].[name,logConfiguration]' --output json"
  description = "The registered log configuration for both containers, as ECS stored it. This is the authoritative answer to \"where are the logs being sent\" - the options here are exactly what the agent turns into the Fluent Bit configuration file, and a typo in an option name is accepted silently at every earlier stage"
}
# The two image references handed back out, so the root reports what the task actually pulls rather than
# keeping its own copy of the reference (rules.md B-5). Nothing checks that these match what was pushed:
# a tag that does not exist in the repository is not an error at apply, it is a service whose tasks stop
# with CannotPullContainerError.
output "application_image_uri" {
  value       = var.application_image_uri
  description = "Image reference the application container pulls"
}
output "log_router_image_uri" {
  value       = var.log_router_image_uri
  description = "Image reference the log router container pulls"
}
