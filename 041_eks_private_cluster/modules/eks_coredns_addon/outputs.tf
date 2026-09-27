output "coredns_addon_arn" {
  value       = aws_eks_addon.coredns.arn
  description = "ARN of the coredns EKS addon"
}
