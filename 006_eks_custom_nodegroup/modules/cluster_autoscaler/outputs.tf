output "release_name" {
  value       = helm_release.cluster_autoscaler.name
  description = "Name of the installed cluster-autoscaler Helm release"
}
output "release_status" {
  value       = helm_release.cluster_autoscaler.status
  description = "Status of the installed cluster-autoscaler Helm release"
}
output "controller_role_arn" {
  value       = aws_iam_role.cluster_autoscaler_iam_role.arn
  description = "ARN of the IAM role the cluster autoscaler assumes through IRSA"
}
output "namespace" {
  value       = var.namespace
  description = "Namespace the cluster autoscaler runs in, re-exposed so callers reference one source of truth (rules.md #5)"
}
