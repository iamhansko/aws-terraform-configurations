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

output "cluster_security_group_id" {
  value       = aws_eks_cluster.eks_cluster.vpc_config[0].cluster_security_group_id
  description = "ID of the EKS cluster's primary security group"
}

output "cluster_role_arn" {
  value       = aws_iam_role.eks_cluster_iam_role.arn
  description = "ARN of the EKS cluster's IAM role"
}
