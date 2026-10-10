output "arn" {
  value       = aws_sns_topic.topic.arn
  description = "ARN of the topic, which the matchmaking configuration names as its notification target"
}
output "name" {
  value       = aws_sns_topic.topic.name
  description = "Name of the topic"
}
