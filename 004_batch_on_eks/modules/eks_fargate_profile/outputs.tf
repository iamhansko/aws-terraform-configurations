output "fargate_profile_arn" {
  value       = aws_eks_fargate_profile.fargate_profile.arn
  description = "ARN of the EKS Fargate profile"
}

output "pod_execution_role_arn" {
  value       = aws_iam_role.fargate_pod_execution_iam_role.arn
  description = "ARN of the Fargate pod execution IAM role"
}
