output "cluster_name" {
  value       = aws_ecs_cluster.ecs_cluster.name
  description = "Name of the cluster. The launch template userdata writes this into /etc/ecs/ecs.config, and the three services and the capacity provider association all name it - one value they every read (rules.md B-5)"
}
output "cluster_arn" {
  value       = aws_ecs_cluster.ecs_cluster.arn
  description = "ARN of the cluster"
}
output "container_insights" {
  value       = var.container_insights
  description = "The containerInsights mode in effect, handed back out so the root can report which one is being paid for without restating the default (rules.md B-5)"
}
output "cluster_status_command" {
  value       = "aws ecs describe-clusters --clusters ${aws_ecs_cluster.ecs_cluster.name} --include SETTINGS --query 'clusters[0].[status,registeredContainerInstancesCount,runningTasksCount,pendingTasksCount,settings]' --output json"
  description = "Registered instances and running against pending task counts in one call. pendingTasksCount staying above zero while registeredContainerInstancesCount is healthy points at the image or at task ENI capacity rather than at the cluster"
}
output "container_instances_command" {
  value       = "aws ecs list-container-instances --cluster ${aws_ecs_cluster.ecs_cluster.name} --query containerInstanceArns --output table"
  description = "Which container instances have registered. An empty list next to a healthy Auto Scaling group is the signature of instances that cannot reach the ECS control plane - the revoked egress rule - or whose role lacks AmazonEC2ContainerServiceforEC2Role. Neither is reported as an error anywhere, because an instance that never registers never becomes an ECS object that could report one"
}
