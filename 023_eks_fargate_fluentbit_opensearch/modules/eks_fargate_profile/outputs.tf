output "fargate_profile_name" {
  value       = aws_eks_fargate_profile.fargate_profile.fargate_profile_name
  description = "Name of the EKS Fargate profile"
}
output "fargate_profile_arn" {
  value       = aws_eks_fargate_profile.fargate_profile.arn
  description = "ARN of the EKS Fargate profile"
}
output "namespace" {
  value       = var.namespace
  description = "Namespace this profile selects, re-exposed so the caller's verification commands do not restate it (rules.md B-5)"
}
output "pod_execution_role_arn" {
  value       = aws_iam_role.fargate_pod_execution_iam_role.arn
  description = "ARN of the Fargate pod execution IAM role this module created"
}
output "pod_execution_role_name" {
  value       = aws_iam_role.fargate_pod_execution_iam_role.name
  description = "Name of the Fargate pod execution IAM role. Exposed alongside the ARN because an inline policy is attached by role name, not by ARN - which is how the logging module gets its CloudWatch permission onto the identity Fluent Bit actually writes as (rules.md B-6)"
}
