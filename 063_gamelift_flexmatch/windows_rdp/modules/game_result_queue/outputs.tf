output "queue_url" {
  value       = aws_sqs_queue.game_result.url
  description = "URL of the queue, written into the game server's config.ini as SQS_ENDPOINT"
}
output "queue_arn" {
  value       = aws_sqs_queue.game_result.arn
  description = "ARN of the queue, for the event source mapping and the send and receive grants"
}
output "queue_name" {
  value       = aws_sqs_queue.game_result.name
  description = "Name of the queue"
}
