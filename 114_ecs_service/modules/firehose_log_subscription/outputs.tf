output "log_group_name" {
  value       = aws_cloudwatch_log_group.log_group.name
  description = "Name of the subscribed log group. The task definition's awslogs-group comes from here, so the containers write to exactly the group the filter is attached to (rules.md B-5)"
}
output "log_group_arn" {
  value       = aws_cloudwatch_log_group.log_group.arn
  description = "ARN of the subscribed log group, for scoping a task role's log permissions to it"
}
output "subscription_filter_name" {
  value       = aws_cloudwatch_log_subscription_filter.subscription.name
  description = "Name of the subscription filter"
}
output "tail_command" {
  value       = "aws logs tail ${aws_cloudwatch_log_group.log_group.name} --follow --since 10m"
  description = "The events as CloudWatch receives them. Each one is handed to Firehose as it arrives; the S3 copy appears only once the stream's buffer flushes"
}
output "describe_subscription_command" {
  value       = "aws logs describe-subscription-filters --log-group-name ${aws_cloudwatch_log_group.log_group.name} --query 'subscriptionFilters[].[filterName,destinationArn]' --output table"
  description = "Which stream the group is subscribed to"
}
