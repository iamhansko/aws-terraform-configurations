output "name" {
  value       = aws_ecr_repository.repository.name
  description = "Name of the repository. The GitHub Actions workflow passes it as ECR_REPOSITORY, so the workflow and this resource are one value (rules.md B-5)"
}
output "arn" {
  value       = aws_ecr_repository.repository.arn
  description = "ARN of the repository, so a caller granting push access can scope it to this one rather than to every repository in the account (rules.md A-5)"
}
output "repository_url" {
  value       = aws_ecr_repository.repository.repository_url
  description = "Host and path to tag and push to, without a tag"
}
output "image_uri" {
  value       = "${aws_ecr_repository.repository.repository_url}:${var.image_tag}"
  description = "The full reference the workbench pushes and the task definition pulls, assembled once here rather than in both places so the tag cannot differ between the push and the pull (rules.md B-5)"
}
output "image_tag" {
  value       = var.image_tag
  description = "The moving tag, handed back so the caller's verification step can ask ECR for exactly the tag that was pushed (rules.md B-5)"
}
# The registry host on its own, which is what docker login takes. A login against the full repository URL
# including the path is accepted by the docker CLI and then does not match on push, so the push retries
# anonymously and fails with "no basic auth credentials" - which reads as a permissions problem.
output "registry_url" {
  value       = split("/", aws_ecr_repository.repository.repository_url)[0]
  description = "Registry host for docker login, split off the repository URL rather than rebuilt from the account ID and region (rules.md B-5)"
}
output "docker_login_command" {
  value       = "aws ecr get-login-password --region ${data.aws_region.current.region} | docker login --username AWS --password-stdin ${split("/", aws_ecr_repository.repository.repository_url)[0]}"
  description = "The login the workbench runs before pushing, exposed so the same string can be pasted onto the box by hand when a push has failed"
}
output "list_images_command" {
  value       = "aws ecr describe-images --repository-name ${aws_ecr_repository.repository.name} --query 'sort_by(imageDetails,&imagePushedAt)[].[imagePushedAt,imageTags,imageSizeInBytes]' --output table"
  description = "Every image in the repository, oldest first. An empty table when the service reports CannotPullContainerError means the seed push never landed, and the reason is in the workbench's cloud-init log rather than anywhere in ECS"
}
