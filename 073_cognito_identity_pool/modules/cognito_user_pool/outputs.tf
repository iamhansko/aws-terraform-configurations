output "user_pool_id" {
  value       = aws_cognito_user_pool.pool.id
  description = "ID of the user pool"
}
output "user_pool_arn" {
  value       = aws_cognito_user_pool.pool.arn
  description = "ARN of the user pool, which an API Gateway Cognito authorizer names"
}
output "user_pool_endpoint" {
  value       = aws_cognito_user_pool.pool.endpoint
  description = "Issuer host and path of the pool (cognito-idp.<region>.amazonaws.com/<pool id>), which an identity pool names as its provider"
}
output "client_id" {
  value       = aws_cognito_user_pool_client.client.id
  description = "ID of the app client"
}
output "domain" {
  value       = aws_cognito_user_pool_domain.domain.domain
  description = "Prefix of the hosted domain"
}
output "hosted_domain_url" {
  value       = "https://${aws_cognito_user_pool_domain.domain.domain}.auth.${data.aws_region.current.region}.amazoncognito.com"
  description = "Base URL of managed login"
}
output "oauth_scopes" {
  value       = aws_cognito_user_pool_client.client.allowed_oauth_scopes
  description = "Every scope the client may request, standard and custom (rules.md B-5)"
}
output "custom_scopes" {
  value       = local.custom_scopes
  description = "The resource server's scopes as clients request them, <identifier>/<scope>. An API method's authorization_scopes names these (rules.md B-5)"
}
output "group_names" {
  value       = sort(keys(aws_cognito_user_group.group))
  description = "Names of the groups created"
}
output "openid_configuration_url" {
  value       = "https://cognito-idp.${data.aws_region.current.region}.amazonaws.com/${aws_cognito_user_pool.pool.id}/.well-known/openid-configuration"
  description = "The pool's OpenID Connect discovery document"
}
output "user_status_command" {
  value       = "aws cognito-idp list-users --user-pool-id ${aws_cognito_user_pool.pool.id} --query 'Users[].[Username,UserStatus,UserCreateDate,Attributes[?Name==`email_verified`].Value|[0]]' --output table"
  description = "Every user with their status and whether their email is verified. UNCONFIRMED with false means a confirmation code was sent and never entered"
}
output "configuration_check_command" {
  value       = "aws cognito-idp describe-user-pool --user-pool-id ${aws_cognito_user_pool.pool.id} --query 'UserPool.[MfaConfiguration,AutoVerifiedAttributes,LambdaConfig.PreTokenGenerationConfig]' --output json"
  description = "MFA, auto-verification and the pre token trigger as Cognito holds them. All three were casualties of the update-user-pool call the _monolithic template made"
}
