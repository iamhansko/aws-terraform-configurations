output "rule_name" {
  value       = aws_cloudwatch_event_rule.ecr_push.name
  description = "Name of the EventBridge rule"
}
output "rule_arn" {
  value       = aws_cloudwatch_event_rule.ecr_push.arn
  description = "ARN of the rule"
}
output "enabled" {
  value       = var.enabled
  description = "Whether the rule is active, re-exposed because a disabled rule is indistinguishable from a missing one when a push does not start anything (rules.md B-5)"
}
output "watched_image" {
  value       = "${var.repository_name}:${var.image_tag}"
  description = "What the rule matches on, re-exposed so a caller can compare it against what the pipeline's source stage reads - a rule and a source that disagree produce executions that deploy nothing and report success"
}
output "failed_invocation_command" {
  value       = "aws cloudwatch get-metric-statistics --namespace AWS/Events --metric-name FailedInvocations --dimensions Name=RuleName,Value=${aws_cloudwatch_event_rule.ecr_push.name} --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) --period 300 --statistics Sum --output table"
  description = "Whether the rule fired and failed to start the pipeline. A rule whose role cannot start the pipeline reports nothing anywhere else - not in the pipeline's history, because no execution was created, and not in the rule, because it matched successfully"
}
