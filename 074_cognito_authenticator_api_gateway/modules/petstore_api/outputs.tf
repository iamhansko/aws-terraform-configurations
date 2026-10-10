output "rest_api_id" {
  value       = aws_api_gateway_rest_api.api.id
  description = "ID of the REST API, which the workshop's web app configuration takes as WS_MOCK_API_ID"
}
output "stage_name" {
  value       = aws_api_gateway_stage.stage.stage_name
  description = "Stage name - not the stage resource's id, which is ags-<api id>-<stage> and is what the conversion first put in these URLs (rules.md B-5)"
}
output "pets_url" {
  value       = "${aws_api_gateway_stage.stage.invoke_url}/pets"
  description = "URL of GET /pets"
}
output "unauthorized_command" {
  value       = "curl -s -o /dev/null -w '%%{http_code}\\n' ${aws_api_gateway_stage.stage.invoke_url}/pets"
  description = "The call without a token. 401 is the authorizer working"
}
output "authorized_command" {
  value       = "curl -s ${aws_api_gateway_stage.stage.invoke_url}/pets -H \"Authorization: Bearer $ACCESS_TOKEN\""
  description = "The call with an access token in ACCESS_TOKEN. An ID token, or an access token without one of the method's scopes, is a 401 as well"
}
