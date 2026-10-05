output "name" {
  value       = aws_ecr_repository.repository.name
  description = "Name of the repository, which the pipeline's image build stage pushes to and the rendered manifest's image reference is built from (rules.md B-5)"
}
output "arn" {
  value       = aws_ecr_repository.repository.arn
  description = "ARN of the repository, so the image build stage's push permissions can be scoped to this one rather than to every repository in the account (rules.md A-5)"
}
output "repository_url" {
  value       = aws_ecr_repository.repository.repository_url
  description = "The URL of the repository, re-exposed so a reader can compare it against the digest-pinned image the rendered manifest names rather than rebuilding the account-and-region string (rules.md B-5)"
}
output "registry_id" {
  value       = aws_ecr_repository.repository.registry_id
  description = "Account that owns the registry, which a docker login has to name"
}
output "list_images_command" {
  value       = "aws ecr describe-images --repository-name ${aws_ecr_repository.repository.name} --query 'sort_by(imageDetails,&imagePushedAt)[].[imagePushedAt,imageTags[0],imageDigest]' --output table"
  description = "Every image in the repository, oldest first. Every pipeline run pushes over the same tag, so this is where the untagged leftovers show up - and where the lifecycle policy's effect is visible"
}
