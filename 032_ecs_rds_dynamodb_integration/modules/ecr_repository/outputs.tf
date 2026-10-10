output "name" {
  value       = aws_ecr_repository.repository.name
  description = "Name of the repository, which the build's verification step names in aws ecr describe-images"
}
output "arn" {
  value       = aws_ecr_repository.repository.arn
  description = "ARN of the repository, so a caller granting pull access can scope it to this one rather than to every repository in the account (rules.md A-5)"
}
output "repository_url" {
  value       = aws_ecr_repository.repository.repository_url
  description = "Host and path to tag and push to, without a tag. This is the value the _monolithic template's cfn-init commands used as ${"$"}{UserEcr.RepositoryUri}"
}
output "image_uri" {
  value       = "${aws_ecr_repository.repository.repository_url}:${var.image_tag}"
  description = "The full reference the build pushes and the task definition pulls. Assembled once here rather than in both places, so the tag cannot differ between the push and the pull (rules.md B-5)"
}
output "image_tag" {
  value       = var.image_tag
  description = "The tag, handed back out so the verification step can ask ECR for exactly the tag that was pushed (rules.md B-5)"
}
output "registry_url" {
  value       = split("/", aws_ecr_repository.repository.repository_url)[0]
  description = "Registry host on its own, which is what docker login takes. A login against the full repository URL including the path is accepted by the docker CLI and then does not match on push, so the push retries anonymously and fails with \"no basic auth credentials\" - which reads like a permissions problem"
}
output "docker_login_command" {
  value       = "aws ecr get-login-password --region ${data.aws_region.current.region} | docker login --username AWS --password-stdin ${split("/", aws_ecr_repository.repository.repository_url)[0]}"
  description = "The login each build step runs before pushing, exposed so the same string can be pasted onto the workbench by hand when a push has failed"
}
output "list_images_command" {
  value       = "aws ecr describe-images --repository-name ${aws_ecr_repository.repository.name} --query 'sort_by(imageDetails,&imagePushedAt)[].[imagePushedAt,imageTags[0],imageSizeInBytes]' --output table"
  description = "Every image in the repository, oldest first. First thing to look at when a service reports CannotPullContainerError: an empty table means the build association never got as far as pushing, and the answer is in its output rather than anywhere in ECS"
}
