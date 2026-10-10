output "name" {
  value       = aws_ecr_repository.repository.name
  description = "Name of the repository, which the CodeBuild buildspec passes to the docker and ecr commands as IMAGE_REPO_NAME"
}
output "arn" {
  value       = aws_ecr_repository.repository.arn
  description = "ARN of the repository. The CodeBuild role's push permissions are scoped to this rather than to every repository in the account (rules.md A-5)"
}
output "repository_url" {
  value       = aws_ecr_repository.repository.repository_url
  description = "Registry host and repository path, with no tag"
}
output "registry_url" {
  value       = split("/", aws_ecr_repository.repository.repository_url)[0]
  description = "Registry host on its own, which is what docker login takes. A login carrying a repository path is accepted and then fails to match on the push, which surfaces as \"no basic auth credentials\" and reads like a permissions problem"
}
output "seed_image_tag" {
  value       = var.seed_image_tag
  description = "The tag the bastion pushes and the first task definition pulls, re-exposed so neither side restates it (rules.md B-5)"
}
output "seed_image_uri" {
  value       = "${aws_ecr_repository.repository.repository_url}:${var.seed_image_tag}"
  description = "Full reference of the seed image. The one value the bastion's docker build, its push, the completion check in the root and the task definition's image field all read (rules.md B-5)"
}
output "list_images_command" {
  value       = "aws ecr describe-images --repository-name ${aws_ecr_repository.repository.name} --query 'reverse(sort_by(imageDetails,&imagePushedAt))[].[imageTags[0],imagePushedAt]' --output table"
  description = "Command listing the images in the repository, newest first. The seed tag should be present after the first apply and one timestamped tag per pipeline run after that"
}
