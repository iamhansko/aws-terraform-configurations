output "cluster_name" {
  value       = aws_ecs_cluster.ecs_cluster.name
  description = "Name of the cluster. The launch template userdata writes this into /etc/ecs/ecs.config, and the service and the capacity provider association both name it - a single value they all read (rules.md B-5)"
}
output "cluster_arn" {
  value       = aws_ecs_cluster.ecs_cluster.arn
  description = "ARN of the cluster"
}
output "service_connect_defaults" {
  value       = var.service_connect_defaults
  description = "The default Service Connect namespace the cluster was given, or null, handed back so a caller can see which namespace a service that names none will join (rules.md B-5)"
}
output "container_insights" {
  value       = var.container_insights
  description = "The containerInsights mode in effect, handed back out so the root can report which one is being paid for without restating the default (rules.md B-5)"
}
output "container_instances_command" {
  value       = "aws ecs list-container-instances --cluster ${aws_ecs_cluster.ecs_cluster.name} --query containerInstanceArns --output table"
  description = "Which container instances have registered. An empty list with a healthy Auto Scaling group is the signature of instances that cannot reach the ECS control plane or whose role lacks AmazonEC2ContainerServiceforEC2Role - neither of which ECS reports as an error anywhere, because an instance that never registers never appears"
}
output "cluster_status_command" {
  value       = "aws ecs describe-clusters --clusters ${aws_ecs_cluster.ecs_cluster.name} --include SETTINGS --query 'clusters[0].[status,registeredContainerInstancesCount,runningTasksCount,pendingTasksCount,settings]' --output json"
  description = "Registered instances and running versus pending task counts in one call. pendingTasksCount staying above zero while registeredContainerInstancesCount is healthy points at the image or at task ENIs - an awsvpc task needs a free network interface on its instance, not only CPU and memory"
}
