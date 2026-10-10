output "user_pool_id" {
  value       = aws_cognito_user_pool.pool.id
  description = "ID of the user pool, which the server takes as COGNITO_USER_POOL_ID"
}
output "user_pool_arn" {
  value       = aws_cognito_user_pool.pool.arn
  description = "ARN of the user pool, for scoping the task role's Cognito permissions"
}
output "client_id" {
  value       = aws_cognito_user_pool_client.client.id
  description = "ID of the app client, which the server takes as COGNITO_CLIENT_ID"
}
output "list_users_command" {
  value       = "aws cognito-idp list-users --user-pool-id ${aws_cognito_user_pool.pool.id} --query 'Users[].[Username,UserStatus,Attributes[?Name==`preferred_username`].Value|[0]]' --output table"
  description = "Players who have signed up, and whether the server confirmed them"
}
