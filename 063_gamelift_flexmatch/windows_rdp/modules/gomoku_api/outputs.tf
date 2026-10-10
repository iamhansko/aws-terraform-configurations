output "rest_api_id" {
  value       = aws_api_gateway_rest_api.api.id
  description = "ID of the REST API. Depends on the API resource alone, which is what lets the Windows instance take it at boot while every route behind it waits for the functions the instance has not uploaded yet"
}
output "execution_arn" {
  value       = aws_api_gateway_rest_api.api.execution_arn
  description = "Execution ARN of the API, the prefix of every invoke permission's source_arn"
}
output "stage_name" {
  value       = aws_api_gateway_stage.api.stage_name
  description = "Name of the published stage"
}
output "invoke_url" {
  value       = aws_api_gateway_stage.api.invoke_url
  description = "Base URL of the published stage, which is MATCH_SERVER_API in the game clients' config.ini"
}
output "route_urls" {
  value       = { for key, route in var.routes : key => "${aws_api_gateway_stage.api.invoke_url}/${route.path_part}" }
  description = "Full URL of each route, keyed as the caller keyed routes"
}
