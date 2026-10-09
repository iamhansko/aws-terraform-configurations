output "connection_arn" {
  value       = aws_codestarconnections_connection.github.arn
  description = "ARN of the CodeStar connection"
}
output "connection_name" {
  value       = aws_codestarconnections_connection.github.name
  description = "Name of the CodeStar connection"
}
output "connection_status" {
  value       = aws_codestarconnections_connection.github.connection_status
  description = "Whether the connection is usable. A new connection is PENDING until someone completes the GitHub handshake in the console, and Terraform reports the apply as successful either way - so this is surfaced rather than left to be discovered"
}
output "connection_console_url" {
  value       = "https://console.aws.amazon.com/codesuite/settings/connections"
  description = "Where to complete the GitHub handshake that moves the connection from PENDING to AVAILABLE"
}
output "connection_status_command" {
  value       = "aws codestar-connections get-connection --connection-arn ${aws_codestarconnections_connection.github.arn} --query 'Connection.[ConnectionName,ConnectionStatus,ProviderType]' --output table"
  description = "The connection's current status from the API rather than from state, which is the only place the result of the browser handshake shows up"
}
output "bucket_name" {
  value       = aws_s3_bucket.source.id
  description = "Name of the generated bucket the seeded repository zip is uploaded to"
}
output "bucket_arn" {
  value       = aws_s3_bucket.source.arn
  description = "ARN of the source bucket, so a caller granting read access can scope it to this one bucket"
}
output "token_parameter_name" {
  value       = aws_ssm_parameter.github_token.name
  description = "Parameter Store path holding the token, handed back so the seed-commit association reads the same path this module wrote (rules.md B-5)"
}
output "token_parameter_arn" {
  value       = aws_ssm_parameter.github_token.arn
  description = "ARN of the token parameter, so a caller narrowing the workbench's role can scope ssm:GetParameter to it"
}
# No output carries the token itself. It is sensitive, and every output in this root is written into a
# README that an unauthenticated code-server serves (rules.md H-2). The retrieval command is the output
# instead, which is the same trade the key pair module makes for the private key.
output "token_retrieval_command" {
  value       = "aws ssm get-parameter --name ${aws_ssm_parameter.github_token.name} --with-decryption --query Parameter.Value --output text"
  description = "Command that retrieves the GitHub token. A command rather than the token, so neither terraform output nor the README on the workbench contains it"
}
output "github_user" {
  value       = var.github_user
  description = "GitHub account the source credential was registered for, re-exposed so the clone URL and the credential cannot name different owners (rules.md B-5)"
}
