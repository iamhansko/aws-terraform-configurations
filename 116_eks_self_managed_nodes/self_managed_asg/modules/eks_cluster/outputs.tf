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
  description = "Base64-encoded certificate authority data for the cluster, used to configure the kubernetes provider"
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

output "oidc_issuer_host" {
  value       = trimprefix(aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer, "https://")
  description = "OIDC issuer URL with the https:// scheme stripped, for use in IRSA trust policy condition keys"
}

output "service_ipv4_cidr" {
  value       = aws_eks_cluster.eks_cluster.kubernetes_network_config[0].service_ipv4_cidr
  description = "CIDR the cluster allocates Service addresses from, read back from the cluster rather than from the variable so it is the value EKS actually used. A self-managed node's NodeConfig has to carry it (rules.md B-5)"
}

output "cluster_dns_ip" {
  value       = cidrhost(aws_eks_cluster.eks_cluster.kubernetes_network_config[0].service_ipv4_cidr, var.cluster_dns_host_number)
  description = "Address of the cluster DNS Service, derived from the service CIDR rather than written out. A self-managed node's kubelet is told this directly, and a wrong value produces nodes that join Ready and pods that cannot resolve anything"
}
