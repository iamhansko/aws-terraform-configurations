output "connection_arn" {
  value       = aws_codestarconnections_connection.github.arn
  description = "ARN of the CodeStar connection"
}
output "connection_status" {
  value       = aws_codestarconnections_connection.github.connection_status
  description = "Whether the connection is usable. A new connection is PENDING until someone completes the GitHub handshake in the console - Terraform reports the apply as successful either way, so this is surfaced rather than left to be discovered"
}
output "connection_console_url" {
  value       = "https://console.aws.amazon.com/codesuite/settings/connections"
  description = "Where to complete the GitHub handshake that moves the connection from PENDING to AVAILABLE"
}
output "bucket_name" {
  value       = aws_s3_bucket.source.id
  description = "Name of the bucket the seed repository zip is uploaded to"
}
output "bucket_arn" {
  value       = aws_s3_bucket.source.arn
  description = "ARN of the seed repository bucket"
}
# No output carries the token. It is sensitive and every output is written into a README that an
# unauthenticated code-server serves (rules.md H-2).
output "github_user" {
  value       = var.github_user
  description = "GitHub username the source credential was registered for, re-exposed so the repository URL and the credential cannot name different owners (rules.md B-5)"
}
