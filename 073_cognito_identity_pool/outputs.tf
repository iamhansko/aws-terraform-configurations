# Every value here is a projection of local.outputs in main.tf, which the README written onto the workbench
# renders from the same map - so no value expression exists twice, and an output cannot be added without also
# appearing in that README (rules.md B-5/H-2).
#
# description is the one thing that cannot be projected: Terraform rejects an expression in an output's
# description ("Variables not allowed"), so the wording is a literal on both sides.
output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "The workbench. The workshop tree is in ~/workshop, and ~/workshop/ws-env.sh holds every ID below"
}
output "web_app_url" {
  value       = local.outputs.web_app_url.value
  description = "The _monolithic template's 03oooUi output: sign up, sign in, enrol TOTP, call the API and list the bucket, all from the browser"
}
output "cognito_login_url" {
  value       = local.outputs.cognito_login_url.value
  description = "Cognito's own sign-in page, styled by the branding in this root, using the implicit flow - the tokens come back in the callback URL"
}
output "openid_configuration_url" {
  value       = local.outputs.openid_configuration_url.value
  description = "The pool's discovery document: issuer, endpoints and signing keys"
}
output "unauthorized_command" {
  value       = local.outputs.unauthorized_command.value
  description = "401 - the Cognito authorizer rejects it before the backend is reached"
}
output "api_group_command" {
  value       = local.outputs.api_group_command.value
  description = "The API accepts an access token that carries the Engineering group as a scope, and a user who has just signed up is in no group - so the web app's Call APIs tab answers 401 for them. Replace USERNAME and run this, then sign out and in again: the group reaches the token's scopes only when a token is issued"
}
output "authorized_command" {
  value       = local.outputs.authorized_command.value
  description = "Put an access token in ACCESS_TOKEN first. It needs petstore/read, or the Engineering group, which the pre token generation trigger adds to the token as a scope"
}
output "bucket" {
  value       = local.outputs.bucket.value
  description = "The _monolithic template's 06oooS3BucketName output, and exactly what the Access S3 tab's Bucket field takes. The listing runs on identity pool credentials, so sign in first. Anything around the name - this value used to carry the prefixes after it - makes S3 answer 400 InvalidBucketName without CORS headers, which the page shows as Failed to fetch"
}
output "bucket_prefixes" {
  value       = local.outputs.bucket_prefixes.value
  description = "What the Prefix field takes, one at a time. Case matters: a prefix that matches nothing lists nothing, which the page reports as There was a problem"
}
output "guest_credentials_command" {
  value       = local.outputs.guest_credentials_command.value
  description = "The identity pool's unauthenticated flow. The guest role has no permissions, so these credentials can do nothing"
}
output "user_pool_configuration_command" {
  value       = local.outputs.user_pool_configuration_command.value
  description = "All three as Cognito holds them. The _monolithic template set the trigger with update-user-pool, which reset the other two - its 00oooAllowEmailAutoVerification output was the console link for switching email verification back on by hand"
}
output "pre_token_log_command" {
  value       = local.outputs.pre_token_log_command.value
  description = "It runs on every sign-in and token refresh and copies the user's groups into the access token's scopes"
}
output "web_app_deploy_command" {
  value       = local.outputs.web_app_deploy_command.value
  description = "After editing anything under ~/workshop/cognito-web. It rebuilds the front-end bundle and the package and points the function at it - what sam build and sam deploy did when the web app was a SAM stack. Its template is Terraform's now, so the directory has none"
}
output "web_app_log_command" {
  value       = local.outputs.web_app_log_command.value
  description = "The Lambda Web Adapter's lines, then the Express app's"
}
output "user_status_command" {
  value       = local.outputs.user_status_command.value
  description = "UNCONFIRMED with email_verified false means a code was sent and never entered. The web app's Resend Code sends a new one. Cognito's default email leaves no record of delivery, so the masked address the code prompt shows is the only trace of where it went - check spam for no-reply@verificationemail.com"
}
output "private_key_command" {
  value       = local.outputs.private_key_command.value
  description = "Retrieves the generated private key from Parameter Store. No security group opens port 22; this is for the case where the SSM agent is what is broken"
}
