output "rule_name" {
  value       = aws_cloudwatch_event_rule.repository_state_change.name
  description = "Name of the EventBridge rule that starts the pipeline"
}
output "rule_arn" {
  value       = aws_cloudwatch_event_rule.repository_state_change.arn
  description = "ARN of the rule"
}
output "enabled" {
  value       = var.enabled
  description = "Whether the rule is enabled, re-exposed from the input so a pipeline that never starts on a push can be explained from terraform output rather than from the console (rules.md B-5)"
}
output "failed_invocations_command" {
  value       = "aws cloudwatch get-metric-statistics --namespace AWS/Events --metric-name FailedInvocations --dimensions Name=RuleName,Value=${aws_cloudwatch_event_rule.repository_state_change.name} --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) --period 300 --statistics Sum --output table"
  description = "Where a rule that matched but could not start the pipeline shows up. This is the only place that failure appears: the pipeline has no execution to show, so it looks like the push was never noticed"
}
