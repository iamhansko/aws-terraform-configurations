output "vscode" {
  value       = "http://${module.vscode_ec2.public_ip}:8000"
  description = "VsCode EC2"
}

output "eks_cluster_name" {
  value       = module.eks_cluster.cluster_name
  description = "Name of the EKS cluster"
}

output "eks_cluster_endpoint" {
  value       = module.eks_cluster.cluster_endpoint
  description = "EKS cluster API server endpoint"
}

output "batch_job_queue_arn" {
  value       = module.batch.job_queue_arn
  description = "ARN of the AWS Batch job queue"
}

output "batch_job_definition_arn" {
  value       = module.batch.job_definition_arn
  description = "ARN of the AWS Batch job definition"
}
