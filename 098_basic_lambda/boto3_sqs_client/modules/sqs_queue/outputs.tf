output "queue_url" {
  value       = aws_sqs_queue.queue.id
  description = "URL of the queue. This is the value the Lambda function gets as QUEUE_URL and the worker script embeds, and it is the id attribute rather than a separate url attribute - aws_sqs_queue.id is the queue URL"
}
output "queue_arn" {
  value       = aws_sqs_queue.queue.arn
  description = "ARN of the queue, which is what the IAM statements on both sides narrow themselves to. The URL cannot be used for that: an IAM Resource element takes an ARN"
}
output "queue_name" {
  value       = aws_sqs_queue.queue.name
  description = "Name of the queue, for CloudWatch dimensions and console links"
}
output "depth_command" {
  value       = "aws sqs get-queue-attributes --queue-url ${aws_sqs_queue.queue.id} --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible --output table"
  description = "How many messages are waiting, and how many are currently being processed. Terraform cannot know either - they are not resource attributes, they change by the second - so this is a command rather than an output value. The pair matters: messages moving from the first number to the second is the worker picking them up, and both falling to zero is the queue drained"
}
output "receive_command" {
  value       = "aws sqs receive-message --queue-url ${aws_sqs_queue.queue.id} --max-number-of-messages 1 --visibility-timeout 0"
  description = "Reads one message without consuming it - visibility-timeout 0 puts it straight back - so the payload the function wrote can be inspected while the worker is running"
}
output "purge_command" {
  value       = "aws sqs purge-queue --queue-url ${aws_sqs_queue.queue.id}"
  description = "Empties the queue, for restarting the demo without waiting out message_retention_seconds. SQS allows one purge per queue per minute and the deletion takes up to another minute, so a depth that does not drop immediately after this is expected"
}
