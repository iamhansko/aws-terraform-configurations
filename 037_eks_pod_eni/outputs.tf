output "vscode_url" {
  value       = module.vscode_ec2.vscode_url
  description = "URL to access the code-server web UI on the VS Code EC2 instance"
}

output "cluster_name" {
  value       = module.eks_cluster.cluster_name
  description = "Name of the EKS cluster"
}

output "cluster_endpoint" {
  value       = module.eks_cluster.cluster_endpoint
  description = "API server endpoint of the EKS cluster"
}

output "web_ec2_private_ip" {
  value       = module.web_ec2.private_ip
  description = "Private IP address of the nginx demo EC2 instance"
}

output "pod_security_group_id" {
  value       = module.pod_security_group_policy.pod_security_group_id
  description = "ID of the security group assigned to pods via SecurityGroupPolicy"
}
