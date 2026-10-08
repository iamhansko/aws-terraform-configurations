output "capacity_provider_name" {
  value       = aws_ecs_capacity_provider.capacity_provider.name
  description = "Name of the capacity provider. The service's capacity_provider_strategy names this - the name rather than the ARN, because that is what ECS stores and returns (see main.tf)"
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
  description = "Latest version of the launch template, which is the version the Auto Scaling group launches. An instance running an older version is one that was launched before the template last changed - the group does not replace instances on its own"
}
output "security_group_id" {
  value       = aws_security_group.container_instance_security_group.id
  description = "ID of the container instance security group, so a caller can reference it as a source elsewhere"
}
output "iam_role_arn" {
  value       = aws_iam_role.container_instance_iam_role.arn
  description = "ARN of the container instance role"
}
output "iam_role_name" {
  value       = aws_iam_role.container_instance_iam_role.name
  description = "Name of the container instance role"
}
# Inputs handed back out so the caller builds its own outputs and its other modules' inputs from one
# value (rules.md B-5). host_volume_path is the important one: the launch template creates that directory
# and the task definition bind-mounts it, and a root restating the path in both places is how the two
# come to disagree - which is not an error, just an empty directory and writes landing elsewhere.
output "host_volume_path" {
  value       = var.host_volume_path
  description = "Host directory the launch template creates and the task definition is expected to bind-mount"
}
output "instance_types" {
  value       = var.instance_types
  description = "Instance types offered to the mixed instances policy. Under price-capacity-optimized the order is not a preference"
}
output "desired_capacity" {
  value       = var.desired_capacity
  description = "Container instances requested at launch. Only the starting point: ECS managed scaling owns this field afterwards, which is why Terraform ignores changes to it (see main.tf)"
}
output "scaling_activities_command" {
  value       = "aws autoscaling describe-scaling-activities --auto-scaling-group-name ${aws_autoscaling_group.container_instance_asg.name} --max-items 10 --query 'Activities[].[StartTime,StatusCode,Description,StatusMessage]' --output table"
  description = "The group's recent scaling activities. This is where a spot group that is 100 percent spot reports that it could not get capacity - a Failed activity here, rather than anything in ECS, is what explains a cluster with fewer instances than desired"
}
output "container_instance_status_command" {
  value       = "aws ecs list-container-instances --cluster ${var.cluster_name} --query containerInstanceArns --output text | xargs -r aws ecs describe-container-instances --cluster ${var.cluster_name} --container-instances --query 'containerInstances[].[ec2InstanceId,status,agentConnected,runningTasksCount,remainingResources[?name==`MEMORY`].integerValue|[0]]' --output table"
  description = "Which instances registered, whether their agent is connected, and the memory each has left. Instances launched but missing from this table is the signature of the revoked egress rule or a missing AmazonEC2ContainerServiceforEC2Role - see main.tf"
}
output "capacity_provider_status_command" {
  value       = "aws ecs describe-capacity-providers --capacity-providers ${aws_ecs_capacity_provider.capacity_provider.name} --query 'capacityProviders[0].[name,status,autoScalingGroupProvider.autoScalingGroupArn,autoScalingGroupProvider.managedScaling]' --output json"
  description = "The provider as ECS holds it, including the Auto Scaling group ARN it resolved. Worth comparing against the configuration: ECS returns an ARN here whatever was sent, which is why the ARN is what gets sent (see main.tf)"
}
