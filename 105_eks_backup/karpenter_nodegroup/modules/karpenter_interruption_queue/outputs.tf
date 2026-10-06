output "queue_name" {
  value       = aws_sqs_queue.karpenter_interruption_queue.name
  description = "Name of the queue. This is the value Karpenter's chart wants as settings.interruptionQueue - not the URL and not the ARN, which is easy to get wrong because all three identify the same queue (rules.md B-5)"
}
output "queue_url" {
  value       = aws_sqs_queue.karpenter_interruption_queue.url
  description = "URL of the queue, for reading messages from the CLI"
}
output "queue_arn" {
  value       = aws_sqs_queue.karpenter_interruption_queue.arn
  description = "ARN of the queue, for scoping the controller's sqs:ReceiveMessage and sqs:DeleteMessage permissions to it"
}
output "rule_names" {
  value       = { for key, rule in aws_cloudwatch_event_rule.karpenter_interruption : key => rule.name }
  description = "EventBridge rule name per event class, keyed by the class. Useful for checking which of the four are enabled without reading the configuration"
}
output "queue_depth_command" {
  value       = "aws sqs get-queue-attributes --queue-url ${aws_sqs_queue.karpenter_interruption_queue.url} --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible"
  description = "How many notices are waiting. Normally zero, because Karpenter deletes each message as it acts on it - a number that stays above zero means the controller is not polling, which is usually a wrong settings.interruptionQueue or missing SQS permissions"
}
output "receive_message_command" {
  value       = "aws sqs receive-message --queue-url ${aws_sqs_queue.karpenter_interruption_queue.url} --max-number-of-messages 10 --wait-time-seconds 5"
  description = "Reads a notice by hand, which is how to see what EventBridge actually delivered. Note this competes with Karpenter for the message: whichever polls first gets it, so a message read here may never reach the controller"
}
