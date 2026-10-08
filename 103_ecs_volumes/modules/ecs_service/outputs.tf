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
  description = "ARN of the task definition revision the service is running, including the revision number - which is the value to compare against what describe-services reports when a deployment appears to have done nothing"
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
  description = "ARN of the task role, assumed by the process inside the container"
}
output "task_execution_role_arn" {
  value       = aws_iam_role.ecs_task_execution_role.arn
  description = "ARN of the task execution role, assumed by the ECS agent to pull the image and open the log stream"
}
output "log_group_name" {
  value       = aws_cloudwatch_log_group.ecs_task_log_group.name
  description = "CloudWatch log group the container writes to"
}
# Inputs handed back out so the root reports the paths that are actually in effect rather than keeping
# its own copy of them (rules.md B-5). These two are the pair that has to agree with the launch template
# and with the built image respectively, so having them visible in terraform output is how a mismatch
# gets noticed - it produces no error anywhere.
output "host_volume_path" {
  value       = var.host_volume_path
  description = "Directory on the container instance the task bind-mounts"
}
output "container_mount_path" {
  value       = var.container_mount_path
  description = "Path inside the container the host directory appears at"
}
output "image_uri" {
  value       = var.image_uri
  description = "Image reference the task pulls"
}
# Terraform cannot know which tasks are running, which instance each landed on, or what the container
# wrote - all of that is decided by ECS after apply returns. So these are commands rather than values.
output "service_status_command" {
  value       = "aws ecs describe-services --cluster ${var.cluster_name} --services ${aws_ecs_service.ecs_service.name} --query 'services[0].[status,desiredCount,runningCount,pendingCount,deployments[0].rolloutState,deployments[0].rolloutStateReason]' --output json"
  description = "Desired against running counts and the rollout state. runningCount below desiredCount with the rollout state at IN_PROGRESS for more than a few minutes is the signal to read service_events_command"
}
output "service_events_command" {
  value       = "aws ecs describe-services --cluster ${var.cluster_name} --services ${aws_ecs_service.ecs_service.name} --query 'services[0].events[:10].[createdAt,message]' --output table"
  description = "The service's own account of what it has been trying to do. Nearly every failure in this project ends up here rather than anywhere in Terraform: no instance meeting the task's requirements means capacity or memory, and a repeating stopped-task message means the image"
}
output "stopped_task_reason_command" {
  value       = "aws ecs list-tasks --cluster ${var.cluster_name} --service-name ${aws_ecs_service.ecs_service.name} --desired-status STOPPED --query taskArns --output text | xargs -r aws ecs describe-tasks --cluster ${var.cluster_name} --tasks --query 'tasks[].[stoppedReason,containers[0].reason]' --output table"
  description = "Why the stopped tasks stopped. CannotPullContainerError with a manifest-not-found reason means the image was never pushed; one naming linux/arm64 means it was pushed from the wrong architecture"
}
output "running_task_placement_command" {
  value       = "aws ecs list-tasks --cluster ${var.cluster_name} --service-name ${aws_ecs_service.ecs_service.name} --desired-status RUNNING --query taskArns --output text | xargs -r aws ecs describe-tasks --cluster ${var.cluster_name} --tasks --query 'tasks[].[lastStatus,availabilityZone,containerInstanceArn]' --output table"
  description = "Where the running tasks ended up. Two tasks in two different zones on two different instance ARNs is the placement strategies working; both on one instance means there was only one instance to choose from"
}
output "container_log_command" {
  value       = "aws logs tail ${aws_cloudwatch_log_group.ecs_task_log_group.name} --follow --since 5m"
  description = "The container's output as it runs - the dd summary and the du line, once a second per task. This is the actual result of the project: the disk usage figure climbing and then flattening is the retention loop deleting the oldest files"
}
output "host_volume_contents_command" {
  value       = "aws ecs list-container-instances --cluster ${var.cluster_name} --query 'containerInstanceArns[0]' --output text | xargs -r -I {} aws ecs describe-container-instances --cluster ${var.cluster_name} --container-instances {} --query 'containerInstances[0].ec2InstanceId' --output text | xargs -r -I {} aws ssm start-session --target {} --document-name AWS-StartInteractiveCommand --parameters command='ls -la ${var.host_volume_path}; df -h ${var.host_volume_path}'"
  description = "The bind mount seen from the host, on the first registered container instance. This is the one check that distinguishes a working bind mount from a container writing into its own layer: the files are here, owned by the instance, and df shows the instance's root volume filling rather than a container filesystem"
}
