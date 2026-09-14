output "vscode" {
  value       = "http://${module.vscode_ec2.public_ip}:8000"
  description = "Public IP Address of the VS Code Server EC2 instance"
}

output "eks_cluster_name" {
  value       = module.eks_cluster.cluster_name
  description = "Name of the EKS cluster"
}

output "eks_cluster_endpoint" {
  value       = module.eks_cluster.cluster_endpoint
  description = "EKS cluster API server endpoint"
}
