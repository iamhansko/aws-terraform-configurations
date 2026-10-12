# Plain outputs rather than the local.outputs map and workbench README that rules.md H-2 describes: this root
# has no vscode_ec2 workbench to write a README onto, so there is nothing for the map to feed.
output "slack_events_url" {
  value       = module.slack_api.route_urls["events"]
  description = "Request URL for the Slack app's Event Subscriptions. Slack verifies it with a challenge request, which needs slack_signing_secret set"
}
output "slack_oauth_redirect_url" {
  value       = module.slack_api.route_urls["oauth_redirect"]
  description = "Redirect URL to add under the Slack app's OAuth & Permissions"
}
output "slack_install_url" {
  value       = module.slack_api.route_urls["install"]
  description = "Open in a browser to install the app into a workspace, once the Slack credentials are set"
}
output "oauth_state_s3_bucket" {
  value       = module.oauth_state_bucket.bucket_arn
  description = "Oauth State S3 Bucket ARN, as the SAM template output it"
}
output "installation_s3_bucket" {
  value       = module.installation_bucket.bucket_arn
  description = "Installation S3 Bucket ARN, as the SAM template output it. It holds every installed workspace's bot token"
}
output "slack_app_function" {
  value       = module.slack_app_function.function_arn
  description = "Slack App Function ARN, as the SAM template output it"
}
output "slack_app_function_environment_variables_url" {
  value       = "https://${local.region}.console.aws.amazon.com/lambda/home?region=${local.region}#/functions/${module.slack_app_function.function_name}?subtab=envVars&tab=configure"
  description = "Opens the Slack app function's Environment variables page in the AWS Lambda console"
}
output "slack_app_function_role" {
  value       = module.slack_app_function.role_arn
  description = "IAM Role for Slack App Function, as the SAM template output it"
}
output "function_log_command" {
  value       = module.slack_app_function.log_tail_command
  description = "Follows the function's log, where a rejected signature, a failed install or a handler error shows up"
}
output "layer_packages" {
  value       = module.layer.packages
  description = "Every distribution in the function's layer, as the builder read it back"
}
output "layer_build_log_command" {
  value       = module.layer.build_log_command
  description = "The layer builder's log, where a failed pip install is recorded in full"
}
