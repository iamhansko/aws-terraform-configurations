output "name" {
  value       = aws_ecr_repository.ecr_repository.name
  description = "Repository name, re-exposed from the input so the build step, the task definition's image reference and the describe-images check all read one value (rules.md B-5)"
}
output "arn" {
  value       = aws_ecr_repository.ecr_repository.arn
  description = "ARN of the repository"
}
output "repository_url" {
  value       = aws_ecr_repository.ecr_repository.repository_url
  description = "The <account>.dkr.ecr.<region>.amazonaws.com/<name> URL. The task definition appends a tag to this; the _monolithic template assembled the same string by hand from data.aws_caller_identity and data.aws_region in two separate places"
}
output "registry_url" {
  value       = split("/", aws_ecr_repository.ecr_repository.repository_url)[0]
  description = "Registry host alone, which is what docker login takes. Derived from repository_url rather than reassembled, so a change of account or region cannot leave the login pointing somewhere else than the push"
}
