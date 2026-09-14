output "repository_name" {
  value       = aws_ecr_repository.ecr.name
  description = "Name of the ECR repository"
}
output "repository_url" {
  value       = aws_ecr_repository.ecr.repository_url
  description = "Full repository URL (<account>.dkr.ecr.<region>.amazonaws.com/<name>), for docker build/push and for image references in pod specs"
}
output "registry_id" {
  value       = aws_ecr_repository.ecr.registry_id
  description = "AWS account ID of the registry holding the repository, for 'aws ecr get-login-password'"
}
output "repository_arn" {
  value       = aws_ecr_repository.ecr.arn
  description = "ARN of the ECR repository, for scoping IAM policies to it"
}
