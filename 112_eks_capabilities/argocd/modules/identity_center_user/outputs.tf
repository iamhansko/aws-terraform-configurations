output "user_id" {
  value       = aws_identitystore_user.user.user_id
  description = "Identity store user id. This is what an Argo CD RBAC role mapping takes as its identity id - not the user name, and not an ARN"
}

output "user_name" {
  value       = aws_identitystore_user.user.user_name
  description = "User name to sign in with"
}

output "identity_store_id" {
  value       = var.identity_store_id
  description = "Identity store the user was created in, re-exposed so the caller reads one value (rules.md B-5)"
}

output "user_check_command" {
  value       = "aws identitystore describe-user --identity-store-id ${var.identity_store_id} --user-id ${aws_identitystore_user.user.user_id} --query '[UserName,DisplayName]' --output table"
  description = "Confirms the user exists in the identity store"
}
