output "url" {
  value       = "${aws_api_gateway_stage.stage.invoke_url}/${var.path_part}"
  description = "The MCP endpoint, the SAM template's MCPServerApi output. Read from the stage, so anything that uses it is created after the stage exists"
}
output "rest_api_id" {
  value       = aws_api_gateway_rest_api.api.id
  description = "ID of the REST API"
}
output "stage_name" {
  value       = aws_api_gateway_stage.stage.stage_name
  description = "Name of the deployed stage"
}
output "authorizer_id" {
  value       = aws_api_gateway_authorizer.token.id
  description = "ID of the TOKEN authorizer"
}
output "authorizer_test_command" {
  value       = "aws apigateway test-invoke-authorizer --rest-api-id ${aws_api_gateway_rest_api.api.id} --authorizer-id ${aws_api_gateway_authorizer.token.id} --headers '{\"${var.authorization_header}\":\"Bearer <token>\"}'"
  description = "Runs the authorizer from API Gateway without a client, with <token> replaced by the real one. A 500 from the MCP URL is the authorizer failing - typically unable to read its parameter - rather than rejecting the token, and this shows its error and log lines"
}
