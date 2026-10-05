output "name" {
  value       = aws_ecr_repository.repository.name
  description = "Name of the repository, which the pipeline's source stage and the EventBridge rule's event pattern both have to name (rules.md B-5)"
}
output "arn" {
  value       = aws_ecr_repository.repository.arn
  description = "ARN of the repository, so the pipeline role's ecr:DescribeImages can be scoped to this one rather than to every repository in the account (rules.md A-5)"
}
output "repository_url" {
  value       = aws_ecr_repository.repository.repository_url
  description = "The URL to tag and push to, re-exposed so the build step on the workbench and the pipeline's source stage both read one value rather than rebuilding the account-and-region string (rules.md B-5)"
}
output "registry_id" {
  value       = aws_ecr_repository.repository.registry_id
  description = "Account that owns the registry, which a docker login has to name"
}
output "list_images_command" {
  value       = "aws ecr describe-images --repository-name ${aws_ecr_repository.repository.name} --query 'sort_by(imageDetails,&imagePushedAt)[].[imagePushedAt,imageTags[0],imageDigest]' --output table"
  description = "Every image in the repository, oldest first. The demo is pushing over \"latest\" repeatedly, so this is where the untagged leftovers show up - and where the lifecycle policy's effect is visible"
}
