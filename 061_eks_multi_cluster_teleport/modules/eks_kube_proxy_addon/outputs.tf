output "kube_proxy_addon_arn" {
  value       = aws_eks_addon.kube_proxy.arn
  description = "ARN of the kube-proxy EKS addon"
}
