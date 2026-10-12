output "rest_api_id" {
  value       = aws_api_gateway_rest_api.api.id
  description = "ID of the REST API"
}
output "invoke_url" {
  value       = aws_api_gateway_stage.stage.invoke_url
  description = "Base URL of the stage, without a trailing slash"
}
output "route_urls" {
  value       = { for key, route in var.routes : key => "${aws_api_gateway_stage.stage.invoke_url}/${route.path}" }
  description = "Full URL of each route, keyed as the routes are"
}
output "api_key_id" {
  value       = var.api_key_required ? aws_api_gateway_api_key.api[0].id : null
  description = "ID of the API key, or null when no key is required. The ID, not the value, so terraform output does not print the key"
}
output "api_key_value_command" {
  value       = var.api_key_required ? "aws apigateway get-api-key --api-key ${aws_api_gateway_api_key.api[0].id} --include-value --query value --output text" : null
  description = "Command that prints the API key, or null when no key is required"
}
