output "user_pool_id" {
  value       = aws_cognito_user_pool.pool.id
  description = "ID of the user pool - the blueprint's UserPoolId output"
}
output "user_pool_arn" {
  value       = aws_cognito_user_pool.pool.arn
  description = "ARN of the user pool, which the load balancer's authenticate-cognito actions name"
}
output "user_pool_tier" {
  value       = aws_cognito_user_pool.pool.user_pool_tier
  description = "Feature plan the pool is on, as Cognito reports it - PLUS while threat protection is on"
}
output "client_id" {
  value       = aws_cognito_user_pool_client.load_balancer.id
  description = "ID of the app client the load balancer authenticates with"
}
output "domain" {
  value       = aws_cognito_user_pool_domain.domain.domain
  description = "Prefix of the hosted UI domain - the blueprint's CognitoDomainName output, and what an authenticate-cognito action takes as user_pool_domain"
}
output "hosted_ui_base_url" {
  value       = local.hosted_ui_base_url
  description = "Base address of the hosted UI"
}
output "logout_url" {
  # The blueprint built this with urllib.parse.quote on the load balancer's DNS name while that name was still
  # an unresolved CDK token, so the URL its signout function redirected to carried logout_uri=https://${Token[...]}
  # percent-encoded - a sign-out Cognito rejected because the URI matched no registered sign-out URL. Here the
  # name is known, and it is the lowercased one the client registers.
  value       = "${local.hosted_ui_base_url}/logout?client_id=${aws_cognito_user_pool_client.load_balancer.id}&logout_uri=${urlencode(local.application_url)}"
  description = "Cognito's sign-out endpoint for this client, returning to the application - where the /signout function redirects after clearing the load balancer's session cookies"
}
output "user_management_console_url" {
  value       = "https://${var.region}.console.aws.amazon.com/cognito/v2/idp/user-pools/${aws_cognito_user_pool.pool.id}/user-management/users?region=${var.region}"
  description = "Console page for creating users, which is how users are added while self sign-up is off"
}
output "pre_sign_up_function_name" {
  value       = one(aws_lambda_function.pre_sign_up[*].function_name)
  description = "Name of the pre sign-up domain check, or null when no domains are configured"
}
