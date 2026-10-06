output "name" {
  value       = aws_ecr_repository.ecr.name
  description = "Name of the repository, read from the resource rather than echoing the variable (rules.md B-5)"
}
output "repository_url" {
  value       = aws_ecr_repository.ecr.repository_url
  description = "Registry host and path the workflow pushes to (<account>.dkr.ecr.<region>.amazonaws.com/<name>)"
}
output "registry_id" {
  value       = aws_ecr_repository.ecr.registry_id
  description = "Account ID owning the registry"
}
output "arn" {
  value       = aws_ecr_repository.ecr.arn
  description = "ARN of the repository"
}
output "list_images_command" {
  value       = "aws ecr list-images --repository-name ${aws_ecr_repository.ecr.name} --query 'imageIds[].imageTag' --output table"
  description = "Command listing the tags the pipeline has pushed. Empty until the first workflow run completes (rules.md H-2)"
}
