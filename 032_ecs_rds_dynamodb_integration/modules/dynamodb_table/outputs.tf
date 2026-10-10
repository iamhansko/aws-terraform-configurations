output "name" {
  value       = aws_dynamodb_table.dynamo_table.name
  description = "Name of the table. The product task definition passes this as TABLE_NAME, and the task role's policy is scoped to this table's ARN - one value behind both (rules.md B-5)"
}
output "arn" {
  value       = aws_dynamodb_table.dynamo_table.arn
  description = "ARN of the table, which is what the task role's DynamoDB policy names instead of \"*\" (rules.md A-5)"
}
output "index_arn_pattern" {
  value       = "${aws_dynamodb_table.dynamo_table.arn}/index/*"
  description = "The table's indexes as a policy resource. There are no secondary indexes today; a Query against one would be denied by an ARN-only policy, and that denial reads as an application error rather than a permissions one, so the pattern is exposed for the task role to include"
}
output "hash_key" {
  value       = aws_dynamodb_table.dynamo_table.hash_key
  description = "Partition key attribute name"
}
output "range_key" {
  value       = aws_dynamodb_table.dynamo_table.range_key
  description = "Sort key attribute name, empty when the table has none - which is the shape the product application's GetItem call needs, since it supplies only the partition key (see main.tf)"
}
output "describe_command" {
  value       = "aws dynamodb describe-table --table-name ${aws_dynamodb_table.dynamo_table.name} --query 'Table.[TableStatus,KeySchema,AttributeDefinitions,ItemCount]' --output json"
  description = "The table as DynamoDB holds it. The KeySchema here is what a GetItem call has to match exactly"
}
output "scan_command" {
  value       = "aws dynamodb scan --table-name ${aws_dynamodb_table.dynamo_table.name} --output json"
  description = "Everything in the table, as DynamoDB holds it rather than as the product application renders it - the stored price is the number string the handler formatted, and a POST of an existing id shows here as one item rather than two"
}
