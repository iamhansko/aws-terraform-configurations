output "cloud_watch_observability_addon_arn" {
  value       = aws_eks_addon.cloud_watch_observability.arn
  description = "ARN of the amazon-cloudwatch-observability EKS addon"
}
output "agent_role_arn" {
  value       = aws_iam_role.cloud_watch_observability_iam_role.arn
  description = "ARN of the IAM role the CloudWatch agent assumes through EKS Pod Identity"
}
output "namespace" {
  value       = var.namespace
  description = "Namespace the addon installs into, re-exposed so callers inspecting its pods reference one source of truth (rules.md B-5)"
}
output "container_log_component_names" {
  value       = sort(keys(var.container_log_components))
  description = "Component names Fluent Bit was given a pipeline for, re-exposed so the log group list below and the component list stay in step (rules.md B-5)"
}
output "log_group_names" {
  value       = [for name in sort(keys(var.container_log_components)) : "/aws/eks/${var.cluster_name}/${name}"]
  description = "CloudWatch Logs group each component's pipeline writes to. Built from the same map the pipelines are rendered from, so this cannot drift from what Fluent Bit actually creates (rules.md B-5)"
}
output "log_insights_url" {
  value       = "https://console.aws.amazon.com/cloudwatch/home#logsV2:logs-insights"
  description = "CloudWatch Logs Insights console, where the queries in the project README are run against the log groups above"
}
