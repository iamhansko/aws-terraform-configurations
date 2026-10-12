output "auto_scaling_group_name" {
  value       = aws_autoscaling_group.instance.name
  description = "Name of the Auto Scaling group, which the admin functions read and resize"
}
output "auto_scaling_group_arn" {
  value       = aws_autoscaling_group.instance.arn
  description = "ARN of the Auto Scaling group"
}
# Depends on the cluster association, not only on the provider: ECS rejects a service whose strategy names a
# provider the cluster does not have yet, and the provider's name alone orders the service after the provider
# but not after the association.
output "capacity_provider_name" {
  value       = aws_ecs_capacity_provider.gpu.name
  description = "Name of the capacity provider, once the cluster has it"
  depends_on  = [aws_ecs_cluster_capacity_providers.cluster]
}
output "instance_role_name" {
  value       = aws_iam_role.instance.name
  description = "Name of the instance role"
}
output "instance_types" {
  value       = var.instance_types
  description = "The instance types the group may launch, re-exposed so the task's memory reservation can be sized from the same list (rules.md B-5)"
}
output "docker_volume_plugin" {
  value       = var.docker_volume_plugin
  description = "The volume plugin the instances install, re-exposed so the task definition names the driver exactly as it was installed (rules.md B-5)"
}
output "scaling_activities_command" {
  value       = "aws autoscaling describe-scaling-activities --auto-scaling-group-name ${aws_autoscaling_group.instance.name} --max-items 5 --query 'Activities[].[StartTime,StatusCode,Description,StatusMessage]' --output table"
  description = "The group's recent launches and terminations. A GPU instance that never appears is explained here - no spot capacity under the price, or a vCPU quota of zero for G instances"
}
