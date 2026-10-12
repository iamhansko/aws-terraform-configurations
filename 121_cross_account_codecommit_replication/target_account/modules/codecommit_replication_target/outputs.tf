output "repository_name" {
  value       = aws_codecommit_repository.target.repository_name
  description = "Name of the target CodeCommit repository."
}

output "repository_arn" {
  value       = aws_codecommit_repository.target.arn
  description = "ARN of the target CodeCommit repository."
}

output "clone_url_http" {
  value       = aws_codecommit_repository.target.clone_url_http
  description = "HTTPS clone URL for the target CodeCommit repository."
}

output "cross_account_role_name" {
  value       = aws_iam_role.cross_account_role.name
  description = "Fixed target role name re-exposed for the source-root handoff (rules.md B-5/I-2)."
}

output "cross_account_role_arn" {
  value       = aws_iam_role.cross_account_role.arn
  description = "ARN of the role the source CodeBuild project assumes."
}

output "trusted_source_role_arn" {
  value       = "arn:${var.partition}:iam::${var.source_account_id}:role/${var.source_codebuild_role_name}"
  description = "Exact future source CodeBuild role ARN allowed by the trust-policy condition."
}
