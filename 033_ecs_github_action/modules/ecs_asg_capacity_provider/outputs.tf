output "capacity_provider_name" {
  value       = aws_ecs_capacity_provider.capacity_provider.name
  description = "Name of the EC2 capacity provider. The generated appspec names it for the replacement task set, so the workflow reads it from here rather than restating it (rules.md B-5)"
}
output "capacity_provider_arn" {
  value       = aws_ecs_capacity_provider.capacity_provider.arn
  description = "ARN of the EC2 capacity provider"
}
output "auto_scaling_group_name" {
  value       = aws_autoscaling_group.container_instance_asg.name
  description = "Name of the Auto Scaling group behind the capacity provider"
}
output "auto_scaling_group_arn" {
  value       = aws_autoscaling_group.container_instance_asg.arn
  description = "ARN of the Auto Scaling group"
}
output "launch_template_id" {
  value       = aws_launch_template.container_instance_launch_template.id
  description = "ID of the container instances' launch template"
}
output "security_group_id" {
  value       = aws_security_group.container_instance_security_group.id
  description = "ID of the container instances' security group, for other modules to reference as an ingress source"
}
output "iam_role_name" {
  value       = aws_iam_role.container_instance_iam_role.name
  description = "Name of the container instances' IAM role, for attaching extra policies from the root module"
}
output "iam_role_arn" {
  value       = aws_iam_role.container_instance_iam_role.arn
  description = "ARN of the container instances' IAM role"
}
output "describe_capacity_command" {
  value       = "aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names ${aws_autoscaling_group.container_instance_asg.name} --query 'AutoScalingGroups[0].[MinSize,DesiredCapacity,MaxSize,length(Instances)]' --output table"
  description = "The group's bounds and its current size. DesiredCapacity differing from what this configuration declares is expected rather than drift: managed scaling owns that field, which is why the group ignores changes to it"
}
