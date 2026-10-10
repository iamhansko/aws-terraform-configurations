output "topic_arn" {
  value       = aws_sns_topic.match_events.arn
  description = "ARN of the topic, the matchmaking configuration's notification target"
}
output "topic_name" {
  value       = aws_sns_topic.match_events.name
  description = "Name of the topic"
}
output "policy_id" {
  value       = aws_sns_topic_policy.match_events.id
  description = "ID of the topic policy. Exposed so a caller ordering on this module knows the publish grant is part of what it waited for"
}
