output "node_role_arn" {
  value       = aws_iam_role.batch_node_iam_role.arn
  description = "ARN of the Batch-managed EC2 node IAM role"
}

output "compute_environment_arn" {
  value       = aws_batch_compute_environment.batch_compute_environment.arn
  description = "ARN of the AWS Batch compute environment"
}

output "job_definition_arn" {
  value       = aws_batch_job_definition.batch_job_definition.arn
  description = "ARN of the AWS Batch job definition"
}

output "job_queue_arn" {
  value       = aws_batch_job_queue.batch_job_queue.arn
  description = "ARN of the AWS Batch job queue"
}

output "namespaces" {
  value       = [for ns in kubectl_manifest.batch_namespace : ns.name]
  description = "Kubernetes namespaces created for AWS Batch job scheduling"
}
