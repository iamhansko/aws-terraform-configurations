output "vpc_cni_addon_arn" {
  value       = aws_eks_addon.vpc_cni.arn
  description = "ARN of the vpc-cni EKS addon"
}
output "configuration_values" {
  value       = aws_eks_addon.vpc_cni.configuration_values
  description = "The JSON the addon was configured with, read back from the resource. Worth reading when a setting appears to have no effect: configuration_values is an opaque string to Terraform, so only the EKS API validates it and only apply reports a mismatch (rules.md E-5)"
}
