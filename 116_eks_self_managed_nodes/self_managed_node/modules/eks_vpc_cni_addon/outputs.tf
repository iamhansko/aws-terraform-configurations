output "vpc_cni_addon_arn" {
  value       = aws_eks_addon.vpc_cni.arn
  description = "ARN of the vpc-cni EKS addon"
}
output "network_policy_enabled" {
  value       = var.enable_network_policy
  description = "Whether the network policy agent was switched on, re-exposed from the input so the value the addon actually received is visible in terraform output rather than only inside a JSON string (rules.md B-5). Null means the key was omitted and EKS applied its own default"
}
output "configuration_values" {
  value       = aws_eks_addon.vpc_cni.configuration_values
  description = "The JSON the addon was configured with. Worth reading when a NetworkPolicy is accepted but not enforced: enableNetworkPolicy has to appear at the top level, and a value nested under env is valid JSON that the addon ignores"
}
