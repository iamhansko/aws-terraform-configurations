output "metrics_server_addon_arn" {
  value       = aws_eks_addon.metrics_server.arn
  description = "ARN of the metrics-server EKS addon"
}
