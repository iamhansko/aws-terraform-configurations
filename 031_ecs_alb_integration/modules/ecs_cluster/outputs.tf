output "cluster_name" {
  value       = aws_ecs_cluster.ecs_cluster.name
  description = "Name of the cluster, which is what the service and every ecs CLI command take"
}
output "cluster_arn" {
  value       = aws_ecs_cluster.ecs_cluster.arn
  description = "ARN of the cluster"
}
