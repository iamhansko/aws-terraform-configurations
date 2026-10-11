output "name" {
  value       = aws_dynamodb_table.sessions.name
  description = "Name of the table, which the MCP server function receives as MCP_SESSION_TABLE"
}
output "arn" {
  value       = aws_dynamodb_table.sessions.arn
  description = "ARN of the table, which the MCP server function's item permissions are scoped to"
}
output "scan_command" {
  value       = "aws dynamodb scan --table-name ${aws_dynamodb_table.sessions.name} --query 'Items[].{session:session_id.S,expires_at:expires_at.N,data:data.M}' --output json"
  description = "Lists the stored sessions. Each MCP initialize creates one, and the get_time tool writes last_time_asked into its data"
}
