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
  description = "Namespace the cluster autoscaler runs in, re-exposed so callers reference one source of truth (rules.md B-5)"
}
output "deployment_name" {
  value       = var.fullname_override == null ? var.release_name : var.fullname_override
  description = "Name of the autoscaler's Deployment, which this release pins with fullnameOverride. Re-exposed so a caller's kubectl commands name the object that actually exists rather than the chart's default <release>-aws-cluster-autoscaler (rules.md B-5)"
}
output "logs_command" {
  value       = "kubectl -n ${var.namespace} logs deploy/${var.fullname_override == null ? var.release_name : var.fullname_override} --tail 100"
  description = "The autoscaler's own reasoning: which node groups it found, which pods it could not place, and what it decided to do. A scale-up that never happens is explained here and nowhere else"
}
output "status_command" {
  value       = "kubectl -n ${var.namespace} get configmap ${var.fullname_override == null ? var.release_name : var.fullname_override}-status -o jsonpath='{.data}'"
  description = "The status ConfigMap the autoscaler maintains: every node group it manages, its current and target size, and the last scale-up or scale-down decision. This is the one place that says whether auto-discovery matched anything at all - an empty node group list means the Auto Scaling group tags did not match, which looks exactly like a cluster that simply does not need more nodes"
}
output "scale_down_unneeded_time" {
  value       = var.scale_down_unneeded_time
  description = "How long a node must sit underutilized before removal, re-exposed so a caller describing the demo states the wait that was actually configured rather than upstream's ten minutes (rules.md B-5)"
}
