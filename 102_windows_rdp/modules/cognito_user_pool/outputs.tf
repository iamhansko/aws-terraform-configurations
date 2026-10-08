output "user_pool_id" {
  value       = aws_cognito_user_pool.user_pool.id
  description = "ID of the user pool, which the game server reads as COGNITO_USER_POOL_ID"
}
output "user_pool_arn" {
  value       = aws_cognito_user_pool.user_pool.arn
  description = "ARN of the user pool, which the game server reads as COGNITO_USER_POOL_ARN. It needs both this and the id: the id addresses the pool in Cognito API calls, the ARN is what an IAM policy or an API Gateway authorizer names"
}
output "user_pool_name" {
  value       = aws_cognito_user_pool.user_pool.name
  description = "Name of the user pool"
}
output "user_pool_endpoint" {
  value       = aws_cognito_user_pool.user_pool.endpoint
  description = "Host the pool's token endpoints live under, for a caller checking reachability from the instance"
}
output "client_id" {
  value       = aws_cognito_user_pool_client.user_pool_client.id
  description = "ID of the app client, which the game server reads as COGNITO_CLIENT_ID"
}
output "client_name" {
  value       = aws_cognito_user_pool_client.user_pool_client.name
  description = "Name of the app client"
}
# Not an output: the client secret. generate_secret is false here, so there is no
# secret to expose - and if a caller turns it on, the value belongs in the
# instance's environment through Secrets Manager rather than in terraform output.
output "describe_user_pool_command" {
  value       = "aws cognito-idp describe-user-pool --user-pool-id ${aws_cognito_user_pool.user_pool.id} --query 'UserPool.{Status:Status,Schema:SchemaAttributes[].Name,UsernameAttributes:UsernameAttributes}'"
  description = "What Cognito actually stored, for checking the schema and sign-in attributes against what this module asked for. Worth reading once after the first apply, because a schema attribute cannot be corrected afterwards without replacing the pool"
}
output "list_users_command" {
  value       = "aws cognito-idp list-users --user-pool-id ${aws_cognito_user_pool.user_pool.id} --query 'Users[].{Name:Username,Status:UserStatus}' --output table"
  description = "Players registered so far. Empty until someone signs up through the game client, which is the expected state right after apply - an empty list is not a sign the pool is misconfigured"
}
