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
  description = "API server endpoint of the EKS cluster. Private only on this project, so it resolves to a useful address only from inside the VPC"
}
output "certificate_authority_data" {
  value       = aws_eks_cluster.eks_cluster.certificate_authority[0].data
  description = "Base64-encoded certificate authority data for the cluster. Exposed for completeness; nothing in this root uses it, because there is no kubectl or helm provider to configure (rules.md E-9)"
}
output "cluster_security_group_id" {
  value       = aws_eks_cluster.eks_cluster.vpc_config[0].cluster_security_group_id
  description = "ID of the EKS cluster's primary security group. Attaching this to the workbench instance is what lets it reach the private API server at all - the group admits traffic from itself, and the control plane's interfaces carry it"
}
output "cluster_role_arn" {
  value       = aws_iam_role.eks_cluster_iam_role.arn
  description = "ARN of the EKS cluster's IAM role"
}
output "oidc_provider_arn" {
  value       = aws_iam_openid_connect_provider.eks_oidc_provider.arn
  description = "ARN of the IAM OIDC provider registered for this cluster, for IRSA trust policies"
}
output "oidc_issuer_host" {
  value       = trimprefix(aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer, "https://")
  description = "OIDC issuer URL with the https:// scheme stripped, for use in IRSA trust policy condition keys"
}
output "endpoint_public_access" {
  value       = var.endpoint_public_access
  description = "Whether the API server has a public endpoint, re-exposed from the input so the one fact that decides how Kubernetes objects are created here is visible in terraform output (rules.md B-5/E-9)"
}
output "service_ipv4_cidr" {
  value       = aws_eks_cluster.eks_cluster.kubernetes_network_config[0].service_ipv4_cidr
  description = "The Service CIDR the cluster actually ended up with. Read back from the resource rather than echoed from the variable, because EKS substitutes its own range if the requested one overlaps the VPC"
}
