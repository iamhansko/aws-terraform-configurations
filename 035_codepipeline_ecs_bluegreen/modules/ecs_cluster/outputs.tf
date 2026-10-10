output "cluster_name" {
  value       = aws_ecs_cluster.ecs_cluster.name
  description = "Name of the cluster. Taken from the resource rather than from the variable, so that reading it creates a dependency edge on the cluster actually existing"
}
output "cluster_arn" {
  value       = aws_ecs_cluster.ecs_cluster.arn
  description = "ARN of the cluster"
}
output "container_instances_command" {
  value       = "aws ecs list-container-instances --cluster ${aws_ecs_cluster.ecs_cluster.name} --query containerInstanceArns --output table"
  description = "Command listing the container instances registered with the cluster. An empty list while the Auto Scaling group reports healthy instances means they cannot reach the ECS endpoint - an instance that never registers is absent rather than broken, so nothing in ECS reports it"
}
output "service_placement_failure_command" {
  value       = "aws ecs describe-clusters --clusters ${aws_ecs_cluster.ecs_cluster.name} --include STATISTICS --query 'clusters[0].statistics' --output table"
  description = "Command printing the cluster's running, pending and registered counts. Zero registered container instances is what the revoked egress rule produced, and the service reports it as being unable to find an instance meeting the task's requirements, which reads like a placement constraint"
}
