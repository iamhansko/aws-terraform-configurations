output "name" {
  value       = aws_sqs_queue.game_result_queue.name
  description = "Name of the queue"
}
output "arn" {
  value       = aws_sqs_queue.game_result_queue.arn
  description = "ARN of the queue, for the fleet role's send grant and game-sqs-process's event source mapping"
}
output "url" {
  value       = aws_sqs_queue.game_result_queue.url
  description = "URL of the queue, which the workbench writes into the game server's config.ini as SQS_ENDPOINT"
}
