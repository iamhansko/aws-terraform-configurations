output "capability_arn" {
  value       = aws_eks_capability.capability.arn
  description = "ARN of the EKS capability"
}

output "capability_name" {
  value       = aws_eks_capability.capability.capability_name
  description = "Name of the EKS capability"
}

output "capability_type" {
  value       = aws_eks_capability.capability.type
  description = "Type of the EKS capability: ACK, KRO or ARGOCD"
}

output "capability_version" {
  value       = aws_eks_capability.capability.version
  description = "Version AWS installed for this capability. Chosen by the service rather than pinned here, which is the point of a managed capability"
}

output "iam_role_arn" {
  value       = aws_iam_role.capability.arn
  description = "ARN of the IAM role AWS assumes to run the capability"
}

output "iam_role_name" {
  value       = aws_iam_role.capability.name
  description = "Name of the IAM role AWS assumes to run the capability"
}

output "argo_cd_server_url" {
  # Computed by the service and empty for non-ARGOCD types. Read through the resource rather than
  # from the input, because this is the one piece of the configuration AWS decides.
  value       = try(aws_eks_capability.capability.configuration[0].argo_cd[0].server_url, null)
  description = "URL of the Argo CD server the capability installed, or null for capability types that do not have one"
}
