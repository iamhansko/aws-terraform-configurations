output "capacity_provider_name" {
  value       = aws_ecs_capacity_provider.managed_instances.name
  description = "Name of the capacity provider, which each service's capacity_provider_strategy names"
}
output "security_group_id" {
  value       = aws_security_group.instances.id
  description = "ID of the instances' security group, for the EFS file system to accept mounts from"
}
output "instance_role_name" {
  value       = aws_iam_role.instance.name
  description = "Generated name of the instance role. Starts with ecsInstanceRole, which is what lets ECS pass it"
}
output "container_instances_command" {
  value       = "aws ecs list-container-instances --cluster ${var.cluster_name} --query containerInstanceArns --output text | xargs -r aws ecs describe-container-instances --cluster ${var.cluster_name} --query 'containerInstances[].[ec2InstanceId,status,agentConnected,runningTasksCount]' --output table --container-instances"
  description = "The managed instances that have registered, and how many tasks each runs. Empty while tasks are PROVISIONING means ECS has not launched or could not register an instance"
}
