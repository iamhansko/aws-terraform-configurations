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
  description = "Issuer host and path of the pool (cognito-idp.<region>.amazonaws.com/<pool id>), re-exposed for anything that names the pool by issuer (rules.md B-5)"
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
output "openid_configuration_url" {
  value       = "https://cognito-idp.${data.aws_region.current.region}.amazonaws.com/${aws_cognito_user_pool.pool.id}/.well-known/openid-configuration"
  description = "The pool's OpenID Connect discovery document"
}
output "configuration_check_command" {
  value       = "aws cognito-idp describe-user-pool --user-pool-id ${aws_cognito_user_pool.pool.id} --query 'UserPool.[MfaConfiguration,AutoVerifiedAttributes,UserPoolTier]' --output json"
  description = "MFA, auto-verification and the feature plan as Cognito holds them"
}
