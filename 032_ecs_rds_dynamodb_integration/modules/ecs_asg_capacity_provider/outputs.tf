output "capacity_provider_name" {
  value       = aws_ecs_capacity_provider.capacity_provider.name
  description = "Name of the capacity provider, which each service's capacity_provider_strategy names. The name rather than the ARN, because that is what ECS stores and returns (see main.tf)"
}
output "capacity_provider_arn" {
  value       = aws_ecs_capacity_provider.capacity_provider.arn
  description = "ARN of the capacity provider"
}
output "auto_scaling_group_name" {
  value       = aws_autoscaling_group.container_instance_asg.name
  description = "Generated name of the Auto Scaling group, for describe-auto-scaling-groups and for reading its scaling activities"
}
output "auto_scaling_group_arn" {
  value       = aws_autoscaling_group.container_instance_asg.arn
  description = "ARN of the Auto Scaling group"
}
output "launch_template_id" {
  value       = aws_launch_template.container_instance_launch_template.id
  description = "ID of the launch template"
}
output "launch_template_latest_version" {
  value       = aws_launch_template.container_instance_launch_template.latest_version
  description = "Latest template version, which is the version the group launches. An instance running an older one was launched before the template last changed - the group does not replace instances on its own"
}
output "security_group_id" {
  value       = aws_security_group.container_instance_security_group.id
  description = "ID of the container instance security group, so a caller can name it as a source elsewhere"
}
output "iam_role_arn" {
  value       = aws_iam_role.container_instance_iam_role.arn
  description = "ARN of the container instance role"
}
output "iam_role_name" {
  value       = aws_iam_role.container_instance_iam_role.name
  description = "Name of the container instance role, for attaching further policies from the root"
}
output "instance_type" {
  value       = var.instance_type
  description = "Instance type in effect, handed back out so the root can report the awsvpc task-per-instance ceiling without restating the default (rules.md B-5)"
}
output "desired_capacity" {
  value       = var.desired_capacity
  description = "Instances requested at launch. The starting point only - ECS managed scaling owns the field afterwards (see main.tf)"
}
output "container_instance_status_command" {
  value       = "aws ecs list-container-instances --cluster ${var.cluster_name} --query containerInstanceArns --output text | xargs -r aws ecs describe-container-instances --cluster ${var.cluster_name} --container-instances --query 'containerInstances[].[ec2InstanceId,status,agentConnected,runningTasksCount,remainingResources[?name==`MEMORY`].integerValue|[0]]' --output table"
  description = "Which instances registered, whether their agent is connected, and the memory each has left. Instances launched but missing from this table is the signature of the revoked egress rule or a missing AmazonEC2ContainerServiceforEC2Role - see main.tf"
}
output "scaling_activities_command" {
  value       = "aws autoscaling describe-scaling-activities --auto-scaling-group-name ${aws_autoscaling_group.container_instance_asg.name} --max-items 10 --query 'Activities[].[StartTime,StatusCode,Description,StatusMessage]' --output table"
  description = "The group's recent scaling activities. A Failed activity here - a zone with no capacity for the instance type, with balanced-only refusing to compensate elsewhere - explains a cluster with fewer instances than desired, where nothing in ECS does"
}
output "capacity_provider_status_command" {
  value       = "aws ecs describe-capacity-providers --capacity-providers ${aws_ecs_capacity_provider.capacity_provider.name} --query 'capacityProviders[0].[name,status,autoScalingGroupProvider.autoScalingGroupArn,autoScalingGroupProvider.managedScaling]' --output json"
  description = "The provider as ECS holds it, including the Auto Scaling group ARN it resolved. Worth comparing against the configuration: ECS returns an ARN here whatever was sent, which is why an ARN is what gets sent (see main.tf)"
}
