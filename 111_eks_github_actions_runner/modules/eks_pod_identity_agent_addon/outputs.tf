output "pod_identity_agent_addon_arn" {
  value       = aws_eks_addon.pod_identity_agent.arn
  description = "ARN of the eks-pod-identity-agent EKS addon"
}
