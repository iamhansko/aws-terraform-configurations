output "capacity_provider_name" {
  value       = aws_ecs_capacity_provider.capacity_provider.name
  description = "Name of the capacity provider, which is what a service's capacity_provider_strategy names - the name rather than the ARN, for the reason the cluster association in main.tf gives"
}
output "capacity_provider_arn" {
  value       = aws_ecs_capacity_provider.capacity_provider.arn
  description = "ARN of the capacity provider"
}
output "auto_scaling_group_name" {
  value       = aws_autoscaling_group.container_instance_asg.name
  description = "Name of the Auto Scaling group holding the container instances"
}
output "auto_scaling_group_arn" {
  value       = aws_autoscaling_group.container_instance_asg.arn
  description = "ARN of the Auto Scaling group"
}
output "launch_template_id" {
  value       = aws_launch_template.container_instance_launch_template.id
  description = "ID of the launch template the group launches from"
}
output "security_group_id" {
  value       = aws_security_group.container_instance_security_group.id
  description = "ID of the container instance security group. With bridge networking the tasks share this group, so this is also the group Fluent Bit's deliveries to CloudWatch Logs leave through"
}
output "iam_role_arn" {
  value       = aws_iam_role.container_instance_iam_role.arn
  description = "ARN of the container instance role"
}
output "iam_role_name" {
  value       = aws_iam_role.container_instance_iam_role.name
  description = "Name of the container instance role, for attaching extra policies from the root module"
}
output "instance_type" {
  value       = var.instance_type
  description = "Instance type in effect, handed back out so the root can report what the tasks have to fit into without restating it (rules.md B-5)"
}
output "instances_command" {
  value       = "aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names ${aws_autoscaling_group.container_instance_asg.name} --query 'AutoScalingGroups[0].Instances[].[InstanceId,AvailabilityZone,LifecycleState,HealthStatus]' --output table"
  description = "The instances the group has, from the Auto Scaling side. Healthy instances here with an empty list from the cluster's own list-container-instances call is the shape that points at egress or at the instance role rather than at ECS"
}
output "session_command" {
  value       = "aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names ${aws_autoscaling_group.container_instance_asg.name} --query 'AutoScalingGroups[0].Instances[0].InstanceId' --output text | xargs -r -I {} aws ssm start-session --target {}"
  description = "A shell on the first container instance. The two things worth looking at from there are /var/log/ecs/ecs-agent.log, for why an instance did not register, and the generated Fluent Bit configuration under /var/lib/ecs/data/firelens/<task-id>/config, which is the file FireLens built from the task definition's log options"
}
