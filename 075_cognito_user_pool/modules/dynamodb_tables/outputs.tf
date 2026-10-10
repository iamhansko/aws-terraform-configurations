output "table_names" {
  value       = { for key, table in aws_dynamodb_table.table : key => table.name }
  description = "Table name per label"
}
output "table_arns" {
  value       = { for key, table in aws_dynamodb_table.table : key => table.arn }
  description = "Table ARN per label, for the task role's policy"
}
output "environment" {
  value       = { for key, table in aws_dynamodb_table.table : "DYNAMODB_TABLE_${upper(key)}" => table.name }
  description = "The environment variables the server reads its table names from, built here so the variable names and the tables cannot drift apart (rules.md B-5)"
}
