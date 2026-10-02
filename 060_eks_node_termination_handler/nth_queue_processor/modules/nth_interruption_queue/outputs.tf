output "queue_name" {
  value       = aws_sqs_queue.nth_interruption_queue.name
  description = "Name of the queue"
}
output "queue_url" {
  value       = aws_sqs_queue.nth_interruption_queue.url
  description = "URL of the queue. This is the value the handler's chart wants as queueURL - not the name and not the ARN, which is easy to get wrong because all three identify the same queue (rules.md B-5)"
}
output "queue_arn" {
  value       = aws_sqs_queue.nth_interruption_queue.arn
  description = "ARN of the queue, for scoping the handler's sqs:ReceiveMessage and sqs:DeleteMessage permissions to it"
}
output "rule_names" {
  value       = { for key, rule in aws_cloudwatch_event_rule.nth_interruption : key => rule.name }
  description = "EventBridge rule name per event class, keyed by the class. Named rules rather than the _monolithic template's generated terraform-<hash>, so this list is readable"
}
output "queue_depth_command" {
  value       = "aws sqs get-queue-attributes --queue-url ${aws_sqs_queue.nth_interruption_queue.url} --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible"
  description = "How many notices are waiting. Normally zero, because the handler deletes each message as it acts on it - a number that stays above zero means it is not polling, which is usually a wrong queueURL or missing SQS permissions on the service account's role"
}
output "receive_message_command" {
  value       = "aws sqs receive-message --queue-url ${aws_sqs_queue.nth_interruption_queue.url} --max-number-of-messages 10 --wait-time-seconds 5"
  description = "Reads a notice by hand, which is how to see what EventBridge actually delivered. Note this competes with the handler for the message: whichever polls first gets it, so a message read here may never reach the handler"
}
output "rule_invocation_metric_command" {
  value       = "aws cloudwatch get-metric-statistics --namespace AWS/Events --metric-name FailedInvocations --dimensions Name=RuleName,Value=${var.name}-spot-interruption --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) --period 300 --statistics Sum"
  description = "Whether EventBridge failed to deliver to the queue. This is the one failure with no other symptom: a rule that matches but cannot write to the queue counts a FailedInvocation and the notice is simply lost, so the node disappears without a drain and nothing in the cluster explains why"
}
