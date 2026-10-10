output "url" {
  # Assembled from the API's ID rather than read from the stage's invoke_url, which is the same string. The
  # user pool needs this URL for its callback, the package needs the user pool's IDs, and the stage comes after
  # the function and so after the package - from the stage, the URL would close that loop.
  value       = "https://${aws_api_gateway_rest_api.api.id}.execute-api.${data.aws_region.current.region}.amazonaws.com/${var.stage_name}"
  description = "Base URL of the web app, the SAM template's CognitoWebAppURL. Known once the API exists, before the function does"
}
output "rest_api_id" {
  value       = aws_api_gateway_rest_api.api.id
  description = "ID of the web app's REST API"
}
output "function_name" {
  # The name, not the function's attribute: the build that produces the function's package writes it into
  # ws-env.sh, and the function cannot exist before that package does.
  value       = local.function_name
  description = "Name of the web app's function, which deploy.sh updates"
}
output "package_bucket" {
  value       = aws_s3_bucket.package.id
  description = "Bucket the workbench uploads the function's package to"
}
output "package_bucket_arn" {
  value       = aws_s3_bucket.package.arn
  description = "ARN of the package bucket, which the caller's wait for the package is scoped to"
}
output "package_key" {
  value       = var.package_key
  description = "Key of the function's package in the package bucket, re-exposed so the upload and the lookup of its checksum name the same object (rules.md B-5)"
}
output "log_tail_command" {
  value       = "aws logs tail ${aws_cloudwatch_log_group.function.name} --follow --since 10m"
  description = "The web app's output: the adapter's own lines, then Express's"
}
