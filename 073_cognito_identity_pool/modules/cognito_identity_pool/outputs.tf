output "identity_pool_id" {
  value       = aws_cognito_identity_pool.pool.id
  description = "ID of the identity pool"
}
output "authenticated_role_arn" {
  value       = aws_iam_role.authenticated.arn
  description = "Role a signed-in identity's credentials belong to"
}
output "unauthenticated_role_arn" {
  value       = aws_iam_role.unauthenticated.arn
  description = "Role a guest identity's credentials belong to"
}
output "guest_credentials_command" {
  value       = "IDENTITY_ID=$(aws cognito-identity get-id --identity-pool-id ${aws_cognito_identity_pool.pool.id} --query IdentityId --output text) && aws cognito-identity get-credentials-for-identity --identity-id $IDENTITY_ID --query 'Credentials.[AccessKeyId,Expiration]' --output table"
  description = "Obtains guest credentials with no sign-in and no AWS credentials of your own - the unauthenticated flow, end to end"
}
