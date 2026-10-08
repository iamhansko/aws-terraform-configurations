# A map keyed by the same logical names the caller passed in, rather than six
# named outputs. That is the shape the instance needs: its environment variables
# are DYNAMODB_TABLE_<KEY>, so the caller can render them by iterating this map
# and never has to restate which table is which (rules.md B-5).
#
# The keys come straight through from var.tables, so they are known at plan time
# and a caller may use them as a for_each (rules.md B-8). The values are table
# names, which are not known until apply.
output "table_names" {
  value       = { for key, table in aws_dynamodb_table.table : key => table.name }
  description = "Table name per logical key, which is what the game server reads out of its environment"
}
output "table_arns" {
  value       = { for key, table in aws_dynamodb_table.table : key => table.arn }
  description = "Table ARN per logical key, for a caller writing an IAM policy scoped to these tables rather than to every table in the account"
}
output "table_ids" {
  value       = { for key, table in aws_dynamodb_table.table : key => table.id }
  description = "Table id per logical key. For aws_dynamodb_table this is the table name, exposed separately because that is not obvious from the attribute name"
}
output "table_keys" {
  value       = keys(var.tables)
  description = "The logical keys, handed back so a caller can check what it asked for against what exists without reading its own variable twice (rules.md B-5)"
}
output "describe_tables_command" {
  value       = "for t in ${join(" ", [for key, table in aws_dynamodb_table.table : table.name])}; do aws dynamodb describe-table --table-name $t --query 'Table.{Name:TableName,Status:TableStatus,Keys:KeySchema[].AttributeName,Items:ItemCount}'; done"
  description = "Status and key schema of all the tables in one pass. ACTIVE on every one is the check; a table stuck in CREATING is the only state the game server cannot write to"
}
