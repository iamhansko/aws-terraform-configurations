output "cluster_name" {
  value       = aws_ecs_cluster.cluster.name
  description = "Name of the ECS cluster"
}
output "cluster_arn" {
  value       = aws_ecs_cluster.cluster.arn
  description = "ARN of the ECS cluster"
}
