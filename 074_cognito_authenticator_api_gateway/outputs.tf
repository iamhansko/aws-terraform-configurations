# Every value here is a projection of local.outputs in main.tf, which the README written onto the workbench
# renders from the same map - so no value expression exists twice, and an output cannot be added without also
# appearing in that README (rules.md B-5/H-2).
#
# description is the one thing that cannot be projected: Terraform rejects an expression in an output's
# description ("Variables not allowed"), so the wording is a literal on both sides.
output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "The workbench. The workshop tree is in ~/workshop, and ~/workshop/ws-env.sh holds the IDs below"
}
output "cognito_login_url" {
  value       = local.outputs.cognito_login_url.value
  description = "The _monolithic template's CognitoLoginUrl output: Cognito's own sign-in page, styled by the branding in this root, using the implicit flow. After sign-in the browser lands on the web app's callback page with the tokens in the URL"
}
output "openid_configuration_url" {
  value       = local.outputs.openid_configuration_url.value
  description = "The _monolithic template's CognitoOpenIdConfiguration output: the pool's issuer, endpoints and signing keys"
}
output "unauthorized_command" {
  value       = local.outputs.unauthorized_command.value
  description = "The _monolithic template's TestUrl output. 401 - the Cognito authorizer rejects it before the MOCK integration is reached"
}
output "authorized_command" {
  value       = local.outputs.authorized_command.value
  description = "Put the access_token the callback page shows into ACCESS_TOKEN. It carries petstore/read, the scope the method requires; the id_token does not, and is a 401"
}
output "user_pool_configuration_command" {
  value       = local.outputs.user_pool_configuration_command.value
  description = "MFA, auto-verification and the feature plan as Cognito holds them"
}
output "web_app_deploy_command" {
  value       = local.outputs.web_app_deploy_command.value
  description = "After editing anything under ~/workshop/cognito-web - writing web-ui-js/cognito-sdk.js, for one. It bundles the front end once that file has content, rebuilds the package and points the function at it: what sam build and sam deploy did when the web app was a SAM stack. Its template is Terraform's now, so the directory has none"
}
output "web_app_log_command" {
  value       = local.outputs.web_app_log_command.value
  description = "The Lambda Web Adapter's lines, then the Express app's. Every request to the callback page passes through it"
}
output "private_key_command" {
  value       = local.outputs.private_key_command.value
  description = "Retrieves the generated private key from Parameter Store. No security group opens port 22; this is for the case where the SSM agent is what is broken"
}
