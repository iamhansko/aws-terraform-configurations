output "arn" {
  value       = aws_sns_topic.topic.arn
  description = "ARN of the topic, which the state machine's notification states publish to and which its IAM policy is scoped to (rules.md B-5)"
}
output "name" {
  value       = aws_sns_topic.topic.name
  description = "Name of the topic"
}
output "subscription_count" {
  value       = length(aws_sns_topic_subscription.email)
  description = "How many subscriptions exist. Zero means a publish succeeds and goes nowhere, which is what the _monolithic template produced and is not visible from the state machine's execution history - it records the publish as successful either way (rules.md B-5)"
}
output "pending_subscriptions_command" {
  value       = "aws sns list-subscriptions-by-topic --topic-arn ${aws_sns_topic.topic.arn} --query 'Subscriptions[].[Protocol,Endpoint,SubscriptionArn]' --output table"
  description = "Subscriptions and their state. A SubscriptionArn reading \"PendingConfirmation\" is an email nobody has clicked yet, and it delivers nothing until they do"
}
