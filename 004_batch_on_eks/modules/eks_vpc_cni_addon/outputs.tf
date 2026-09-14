output "vpc_cni_addon_arn" {
  value       = aws_eks_addon.vpc_cni.arn
  description = "ARN of the vpc-cni EKS addon"
}
