output "name" {
  value       = aws_dynamodb_table.player_table.name
  description = "Name of the table"
}
output "arn" {
  value       = aws_dynamodb_table.player_table.arn
  description = "ARN of the table, for the item-level grants in the Lambda roles"
}
output "stream_arn" {
  value       = aws_dynamodb_table.player_table.stream_arn
  description = "ARN of the table's stream, for game-rank-update's event source mapping and its stream-read grant"
}
