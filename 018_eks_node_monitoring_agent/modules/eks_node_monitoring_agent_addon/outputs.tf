output "node_monitoring_agent_addon_arn" {
  value       = aws_eks_addon.node_monitoring_agent.arn
  description = "ARN of the eks-node-monitoring-agent EKS addon"
}
