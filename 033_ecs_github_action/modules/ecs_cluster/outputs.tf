output "cluster_name" {
  value       = aws_ecs_cluster.ecs_cluster.name
  description = "Name of the cluster. The container instances write it into /etc/ecs/ecs.config, the service joins it, the CodeDeploy deployment group names it and the GitHub Actions workflow passes it to the deploy action - one value to all five (rules.md B-5)"
}
output "cluster_arn" {
  value       = aws_ecs_cluster.ecs_cluster.arn
  description = "ARN of the cluster"
}
output "cluster_id" {
  value       = aws_ecs_cluster.ecs_cluster.id
  description = "ID of the cluster, which the provider reports as its ARN"
}
output "list_container_instances_command" {
  value       = "aws ecs list-container-instances --cluster ${aws_ecs_cluster.ecs_cluster.name} --query containerInstanceArns --output table"
  description = "The registered container instances. An empty list while the Auto Scaling group reports healthy instances is the signature of a container instance that cannot reach the ECS endpoint - an instance that never registers never becomes an ECS object that could report a problem, and the service then blames placement constraints instead"
}
