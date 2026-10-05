output "rule_name" {
  value       = aws_cloudwatch_event_rule.object_created.name
  description = "Name of the EventBridge rule"
}
output "rule_arn" {
  value       = aws_cloudwatch_event_rule.object_created.arn
  description = "ARN of the rule"
}
output "enabled" {
  value       = var.enabled
  description = "Whether the rule is active, re-exposed because a disabled rule is indistinguishable from a missing one when an upload starts nothing (rules.md B-5)"
}
output "watched_object" {
  value       = "s3://${var.bucket_name}/${var.object_key}"
  description = "What the rule matches on, re-exposed so a caller can compare it against what the pipeline's source stage reads - a rule and a source that disagree produce executions that redeploy the previous archive and report success"
}
output "failed_invocation_command" {
  value       = "aws cloudwatch get-metric-statistics --namespace AWS/Events --metric-name FailedInvocations --dimensions Name=RuleName,Value=${aws_cloudwatch_event_rule.object_created.name} --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) --period 300 --statistics Sum --output table"
  description = "Whether the rule fired and failed to start the pipeline. A rule whose role cannot start the pipeline reports nothing anywhere else - not in the pipeline's history, because no execution was created, and not in the rule, because it matched successfully"
}
