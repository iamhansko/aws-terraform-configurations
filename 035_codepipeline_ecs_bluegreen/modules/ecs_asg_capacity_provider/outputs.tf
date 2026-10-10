output "capacity_provider_name" {
  value       = aws_ecs_capacity_provider.capacity_provider.name
  description = "Name of the capacity provider. The name rather than the ARN, because that is what PutClusterCapacityProviders and a service's capacity_provider_strategy document and what ECS reads back - see the module for what an ARN written there does to every subsequent plan"
}
output "capacity_provider_arn" {
  value       = aws_ecs_capacity_provider.capacity_provider.arn
  description = "ARN of the capacity provider"
}
output "auto_scaling_group_name" {
  value       = aws_autoscaling_group.container_instance_asg.name
  description = "Generated name of the container instance Auto Scaling group"
}
output "auto_scaling_group_arn" {
  value       = aws_autoscaling_group.container_instance_asg.arn
  description = "ARN of the Auto Scaling group, which is what the capacity provider is built on"
}
output "launch_template_id" {
  value       = aws_launch_template.container_instance_launch_template.id
  description = "ID of the container instance launch template"
}
output "security_group_id" {
  value       = aws_security_group.container_instance_security_group.id
  description = "ID of the container instance security group"
}
output "iam_role_name" {
  value       = aws_iam_role.container_instance_iam_role.name
  description = "Generated name of the container instance role"
}
output "iam_role_arn" {
  value       = aws_iam_role.container_instance_iam_role.arn
  description = "ARN of the container instance role"
}
output "scaling_activities_command" {
  value       = "aws autoscaling describe-scaling-activities --auto-scaling-group-name ${aws_autoscaling_group.container_instance_asg.name} --max-items 10 --query 'Activities[].[StartTime,StatusCode,Description]' --output table"
  description = "Command printing the group's recent scaling activities. An entirely spot group reports a failure to obtain capacity here and nowhere else, and apply will have succeeded regardless"
}
output "container_instance_status_command" {
  value       = "aws ecs list-container-instances --cluster ${var.cluster_name} --query containerInstanceArns --output text | xargs -r aws ecs describe-container-instances --cluster ${var.cluster_name} --container-instances --query 'containerInstances[].[ec2InstanceId,status,agentConnected,runningTasksCount]' --output table"
  description = "Command printing each registered container instance with its agent connection state and running task count. Instances launched but missing here is the signature of an instance that cannot reach the ECS endpoint - the revoked egress rule this module describes, or a missing route to a NAT gateway"
}
