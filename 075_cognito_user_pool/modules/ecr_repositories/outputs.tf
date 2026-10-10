output "repository_urls" {
  value       = { for key, repo in aws_ecr_repository.repository : key => repo.repository_url }
  description = "Repository URL per label, for the build to tag with and the task definitions to pull from (rules.md B-5)"
}
output "repository_arns" {
  value       = { for key, repo in aws_ecr_repository.repository : key => repo.arn }
  description = "Repository ARN per label, for scoping a pull permission to one repository"
}
output "repository_names" {
  value       = { for key, repo in aws_ecr_repository.repository : key => repo.name }
  description = "Repository name per label"
}
output "registry" {
  value       = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.region}.amazonaws.com"
  description = "The registry host, which docker login takes"
}
