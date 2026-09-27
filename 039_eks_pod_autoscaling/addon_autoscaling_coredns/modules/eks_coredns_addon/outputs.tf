output "coredns_addon_arn" {
  value       = aws_eks_addon.coredns.arn
  description = "ARN of the coredns EKS addon"
}
output "autoscaling_enabled" {
  value       = var.autoscaling_enabled
  description = "Whether the addon is managing CoreDNS replicas itself, re-exposed so the caller's notes match what was actually configured (rules.md B-5)"
}
output "autoscaling_range" {
  value       = var.autoscaling_enabled ? "${var.autoscaling_min_replicas}-${var.autoscaling_max_replicas}" : null
  description = "The replica range the addon's autoscaler works within, or null when autoscaling is off"
}
