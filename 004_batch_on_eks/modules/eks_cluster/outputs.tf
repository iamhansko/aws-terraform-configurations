output "cluster_name" {
  value       = aws_eks_cluster.eks_cluster.name
  description = "Name of the EKS cluster"
}

output "cluster_arn" {
  value       = aws_eks_cluster.eks_cluster.arn
  description = "ARN of the EKS cluster"
}

output "cluster_endpoint" {
  value       = aws_eks_cluster.eks_cluster.endpoint
  description = "API server endpoint of the EKS cluster"
}

output "certificate_authority_data" {
  value       = aws_eks_cluster.eks_cluster.certificate_authority[0].data
  description = "Base64-encoded certificate authority data for the cluster, used to configure the kubernetes/helm provider"
}

output "cluster_security_group_id" {
  value       = aws_eks_cluster.eks_cluster.vpc_config[0].cluster_security_group_id
  description = "ID of the EKS cluster's primary security group"
}

output "cluster_role_arn" {
  value       = aws_iam_role.eks_cluster_iam_role.arn
  description = "ARN of the EKS cluster's IAM role"
}

output "oidc_provider_arn" {
  value       = aws_iam_openid_connect_provider.eks_oidc_provider.arn
  description = "ARN of the IAM OIDC provider registered for this cluster (used for IRSA trust policies)"
}

output "oidc_issuer_url" {
  value       = aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer
  description = "Full OIDC issuer URL (including https://) of the cluster"
}

output "oidc_issuer_host" {
  value       = trimprefix(aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer, "https://")
  description = "OIDC issuer URL with the https:// scheme stripped, for use in IRSA trust policy condition keys"
}
