output "service_name" {
  value       = aws_ecs_service.ecs_service.name
  description = "Name of the service"
}
output "service_arn" {
  value       = aws_ecs_service.ecs_service.id
  description = "ARN of the service, which is what this resource's id is"
}
output "task_definition_arn" {
  value       = aws_ecs_task_definition.ecs_task_definition.arn
  description = "ARN of the revision the service is running, revision number included - the value to compare against what describe-services reports when a deployment appears to have done nothing"
}
output "task_definition_family" {
  value       = aws_ecs_task_definition.ecs_task_definition.family
  description = "Task definition family. One per application here, unlike the _monolithic template, where all three shared \"user-taskdef\" - see main.tf"
}
output "task_definition_revision" {
  value       = aws_ecs_task_definition.ecs_task_definition.revision
  description = "Revision registered by this apply. It increments on every apply that changes the definition; old revisions stay registered and are not cleaned up"
}
output "log_group_name" {
  value       = aws_cloudwatch_log_group.ecs_task_log_group.name
  description = "Log group the container writes to. An addition on top of the template, which configured no log driver at all"
}
output "image_uri" {
  value       = var.image_uri
  description = "Image reference the task pulls, handed back out so the root reports what is actually deployed rather than keeping its own copy (rules.md B-5)"
}
output "container_port" {
  value       = var.container_port
  description = "Port the container listens on, handed back out so the caller's curl commands and security group rules read one value (rules.md B-5)"
}
# Terraform cannot know which tasks are running, where they landed or what they answered - ECS decides all
# of that after apply returns, and with wait_for_steady_state false it returns early on purpose. So these
# are commands rather than values (rules.md H-2).
output "service_status_command" {
  value       = "aws ecs describe-services --cluster ${var.cluster_name} --services ${aws_ecs_service.ecs_service.name} --query 'services[0].[status,desiredCount,runningCount,pendingCount,deployments[0].rolloutState,deployments[0].rolloutStateReason]' --output json"
  description = "Desired against running counts and the rollout state. runningCount below desiredCount with the rollout IN_PROGRESS for more than a few minutes is the signal to read the events"
}
output "service_events_command" {
  value       = "aws ecs describe-services --cluster ${var.cluster_name} --services ${aws_ecs_service.ecs_service.name} --query 'services[0].events[:10].[createdAt,message]' --output table"
  description = "The service's own account of what it has been trying to do. Nearly every failure in this project ends up here rather than in Terraform: no instance meeting the task's requirements means memory or task ENI capacity, and a repeating stopped-task message means the image"
}
output "stopped_task_reason_command" {
  value       = "aws ecs list-tasks --cluster ${var.cluster_name} --service-name ${aws_ecs_service.ecs_service.name} --desired-status STOPPED --query taskArns --output text | xargs -r aws ecs describe-tasks --cluster ${var.cluster_name} --tasks --query 'tasks[].[stoppedReason,containers[0].reason]' --output table"
  description = "Why the stopped tasks stopped. CannotPullContainerError with a manifest-not-found reason means the build association never pushed; a ResourceInitializationError naming the secret means the execution role or the task ENI's route out"
}
output "task_private_ips_command" {
  value       = "aws ecs list-tasks --cluster ${var.cluster_name} --service-name ${aws_ecs_service.ecs_service.name} --desired-status RUNNING --query taskArns --output text | xargs -r aws ecs describe-tasks --cluster ${var.cluster_name} --tasks --query 'tasks[].attachments[].details[?name==`privateIPv4Address`].value' --output text"
  description = "The addresses of the running tasks' ENIs. There is no load balancer here, so this is how a request reaches a container - and the addresses only answer from inside the VPC"
}
output "curl_health_command" {
  value       = "curl -s http://$(aws ecs list-tasks --cluster ${var.cluster_name} --service-name ${aws_ecs_service.ecs_service.name} --desired-status RUNNING --query taskArns --output text | xargs -r aws ecs describe-tasks --cluster ${var.cluster_name} --tasks --query 'tasks[0].attachments[0].details[?name==`privateIPv4Address`].value' --output text):${var.container_port}${var.health_check_path}"
  description = "Resolves the first running task's address and requests its health endpoint, from the workbench. {\"status\":\"ok\"} means the image was built, pushed, pulled and started, and that the task security group admits the workbench - the whole chain in one line"
}
output "container_log_command" {
  value       = "aws logs tail ${aws_cloudwatch_log_group.ecs_task_log_group.name} --follow --since 10m"
  description = "The container's output as it runs. The applications return a bare \"Internal Server Error\" to the caller, so the real reason for a failed request - a missing MySQL table, a DynamoDB key schema mismatch - is only here"
}
output "execute_command" {
  value       = "aws ecs execute-command --cluster ${var.cluster_name} --task $(aws ecs list-tasks --cluster ${var.cluster_name} --service-name ${aws_ecs_service.ecs_service.name} --desired-status RUNNING --query 'taskArns[0]' --output text) --container ${var.container_name} --interactive --command /bin/bash"
  description = "A shell inside the first running task. Needs the Session Manager plugin on the machine it is run from, which the workbench's bootstrap installs"
}
