output "source_repository_name" {
  value       = aws_codecommit_repository.source.repository_name
  description = "Name of the source CodeCommit repository."
}

output "source_repository_arn" {
  value       = aws_codecommit_repository.source.arn
  description = "ARN of the source CodeCommit repository."
}

output "source_repository_clone_url_http" {
  value       = aws_codecommit_repository.source.clone_url_http
  description = "HTTPS clone URL of the source repository."
}

output "main_branch" {
  value       = var.main_branch
  description = "Triggered source branch re-exposed from the module (rules.md B-5)."
}

output "source_region" {
  value       = var.source_region
  description = "Source region re-exposed from the module (rules.md B-5)."
}

output "target_region" {
  value       = var.target_region
  description = "Target region re-exposed from the module (rules.md B-5)."
}

output "target_repository_name" {
  value       = var.target_account_repository
  description = "Agreed target repository name re-exposed from the module (rules.md B-5/I-2)."
}

output "source_codebuild_role_arn" {
  value       = aws_iam_role.build.arn
  description = "ARN of the fixed source CodeBuild role trusted by the target account."
}

output "target_cross_account_role_arn" {
  value       = local.target_role_arn
  description = "Exact target role ARN the build is permitted to assume."
}

output "pipeline_name" {
  value       = aws_codepipeline.replication.name
  description = "Name of the replication pipeline."
}

output "pipeline_arn" {
  value       = aws_codepipeline.replication.arn
  description = "ARN of the replication pipeline."
}

output "build_project_name" {
  value       = aws_codebuild_project.mirror.name
  description = "Name of the Git mirror CodeBuild project."
}

output "build_project_arn" {
  value       = aws_codebuild_project.mirror.arn
  description = "ARN of the Git mirror CodeBuild project."
}

output "artifact_bucket_name" {
  value       = aws_s3_bucket.artifacts.bucket
  description = "Generated force-destroy pipeline artifact bucket."
}

output "event_rule_name" {
  value       = aws_cloudwatch_event_rule.source_main.name
  description = "Name of the EventBridge main-branch trigger."
}
