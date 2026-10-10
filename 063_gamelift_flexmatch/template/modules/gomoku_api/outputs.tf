output "id" {
  value       = aws_api_gateway_rest_api.api.id
  description = "Generated ID of the REST API"
}
output "invoke_url" {
  value       = aws_api_gateway_stage.stage.invoke_url
  description = "Base URL of the published stage, https://<id>.execute-api.<region>.amazonaws.com/<stage>. Taken from the stage rather than assembled, so the clients cannot be given a stage that was not published (rules.md B-5)"
}
output "stage_name" {
  value       = aws_api_gateway_stage.stage.stage_name
  description = "Name of the published stage"
}
