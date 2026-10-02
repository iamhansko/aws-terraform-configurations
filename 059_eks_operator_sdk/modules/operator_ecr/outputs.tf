output "repository_name" {
  value       = aws_ecr_repository.operator_ecr.name
  description = "Name of the ECR repository"
}
output "repository_url" {
  value       = aws_ecr_repository.operator_ecr.repository_url
  description = "Registry path the image is pushed to and pulled from, without a tag"
}
output "registry_id" {
  value       = aws_ecr_repository.operator_ecr.registry_id
  description = "Account ID that owns the registry, for the docker login command"
}
output "image_tag" {
  value       = var.image_tag
  description = "Tag the image is built under, re-exposed so the build step and the deployment read one value (rules.md B-5)"
}
output "image" {
  value       = "${aws_ecr_repository.operator_ecr.repository_url}:${var.image_tag}"
  description = "Full image reference. Built here rather than assembled by each caller, so the push and the deploy cannot end up pointing at different tags (rules.md B-5)"
}
output "login_command" {
  value       = "aws ecr get-login-password | docker login --username AWS --password-stdin ${aws_ecr_repository.operator_ecr.registry_id}.dkr.ecr.${split(".", aws_ecr_repository.operator_ecr.repository_url)[3]}.amazonaws.com"
  description = "Authenticates docker against this registry. The host is derived from the repository URL rather than rebuilt from an account ID and region, so it matches whatever ECR actually returned"
}
output "image_list_command" {
  value       = "aws ecr describe-images --repository-name ${aws_ecr_repository.operator_ecr.name} --query 'sort_by(imageDetails,&imagePushedAt)[].{Tags:imageTags,Pushed:imagePushedAt,MB:imageSizeInBytes}' --output table"
  description = "What is actually in the repository. An empty list after an apply means the build step did not reach the push, which is the first thing to check when the operator pods are in ImagePullBackOff"
}
