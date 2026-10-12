output "name" {
  value       = aws_ecs_cluster.cluster.name
  description = "Name of the cluster. The GPU instances write it into their ecs.config, and the admin functions read the service in it by name"
}
output "arn" {
  value       = aws_ecs_cluster.cluster.arn
  description = "ARN of the cluster, which scopes the instances' ECS permissions and the task state change rule"
}
