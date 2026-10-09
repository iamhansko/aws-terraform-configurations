output "cluster_name" {
  value       = aws_ecs_cluster.ecs_cluster.name
  description = "Name of the ECS cluster. Every service, every CodeDeploy deployment group and the dashboard reference it"
}
output "cluster_arn" {
  value       = aws_ecs_cluster.ecs_cluster.arn
  description = "ARN of the ECS cluster"
}
output "capacity_provider_name" {
  value       = aws_ecs_capacity_provider.ecs_capacity_provider.name
  description = "Name of the EC2 capacity provider"
}
output "auto_scaling_group_name" {
  value       = aws_autoscaling_group.ecs_asg.name
  description = "Generated name of the Auto Scaling group"
}
output "security_group_id" {
  value       = aws_security_group.ecs_container_instance_security_group.id
  description = "The container instance security group. Not the group a load balancer needs to reach - the task definitions use awsvpc, so each task has its own interface guarded by the ECS service group"
}
output "iam_role_arn" {
  value       = aws_iam_role.ecs_container_instance_iam_role.arn
  description = "ARN of the container instance role"
}
output "container_instances_command" {
  value       = "aws ecs list-container-instances --cluster ${aws_ecs_cluster.ecs_cluster.name} --query containerInstanceArns --output table"
  description = "Command listing the instances registered with the cluster. An empty list with a healthy Auto Scaling group is the signature of a container instance that cannot reach the ECS endpoint - which is what the _monolithic template's missing egress rule produced"
}
