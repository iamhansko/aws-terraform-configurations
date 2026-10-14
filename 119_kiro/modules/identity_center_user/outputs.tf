output "user_id" {
  value       = aws_identitystore_user.user.user_id
  description = "Identity store user ID, which the password reset and the Kiro subscription both take"
}
output "user_name" {
  value       = aws_identitystore_user.user.user_name
  description = "Sign-in name"
}

output "email" {
  value       = var.email
  description = "Primary work email recorded for the IAM Identity Center user"
}