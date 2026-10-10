output "table_name" {
  value       = aws_dynamodb_table.player_info.name
  description = "Name of the table"
}
output "table_arn" {
  value       = aws_dynamodb_table.player_info.arn
  description = "ARN of the table, for the item-level grants on the functions that read and write players"
}
output "stream_arn" {
  value       = aws_dynamodb_table.player_info.stream_arn
  description = "ARN of the table's stream, which game-rank-update is triggered from"
}
