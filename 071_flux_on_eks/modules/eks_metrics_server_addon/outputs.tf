# No status output. aws_eks_addon does not expose one, so referencing it fails at
# terraform validate with "Unsupported attribute" (rules.md E-5).
output "metrics_server_addon_arn" {
  value       = aws_eks_addon.metrics_server.arn
  description = "ARN of the metrics-server EKS addon"
}
output "addon_version" {
  value       = aws_eks_addon.metrics_server.addon_version
  description = "Version EKS actually installed, read off the resource rather than off the variable - which is null when the version is left to follow the cluster, so the variable would report nothing (rules.md B-5)"
}
output "metrics_check_command" {
  value       = "kubectl top nodes"
  description = "Whether the metrics API is answering. Numbers here mean a HorizontalPodAutoscaler can read CPU; \"error: Metrics API not available\" means it cannot, and every HPA in the cluster is sitting at unknown targets regardless of what the addon's status says"
}
