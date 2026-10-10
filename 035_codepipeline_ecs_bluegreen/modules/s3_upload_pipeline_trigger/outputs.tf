output "event_rule_name" {
  value       = aws_cloudwatch_event_rule.object_created.name
  description = "Name of the EventBridge rule"
}
output "event_rule_arn" {
  value       = aws_cloudwatch_event_rule.object_created.arn
  description = "ARN of the rule"
}
output "role_arn" {
  value       = aws_iam_role.event_rule_iam_role.arn
  description = "ARN of the role the rule assumes to start the pipeline"
}
output "event_pattern_command" {
  value       = "aws events describe-rule --name ${aws_cloudwatch_event_rule.object_created.name} --query '[State,EventPattern]' --output text"
  description = "Command printing the rule's state and pattern. The bucket name and key in the pattern have to match the object actually being written, and an exact-match key means a write to any other key in the bucket is correctly ignored"
}
output "failed_invocations_command" {
  value       = "aws cloudwatch get-metric-statistics --namespace AWS/Events --metric-name FailedInvocations --dimensions Name=RuleName,Value=${aws_cloudwatch_event_rule.object_created.name} --start-time $(date -u -d '-3 hours' +%Y-%m-%dT%H:%M:%SZ) --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) --period 300 --statistics Sum --query 'Datapoints[].[Timestamp,Sum]' --output table"
  description = "Command reading the rule's FailedInvocations metric. This is the only place a rule that matched and then could not start the pipeline is recorded - the pipeline itself shows nothing, so an upload that triggers no execution is either an unmatched pattern or a datapoint here"
}
output "triggered_invocations_command" {
  value       = "aws cloudwatch get-metric-statistics --namespace AWS/Events --metric-name TriggeredRules --dimensions Name=RuleName,Value=${aws_cloudwatch_event_rule.object_created.name} --start-time $(date -u -d '-3 hours' +%Y-%m-%dT%H:%M:%SZ) --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) --period 300 --statistics Sum --query 'Datapoints[].[Timestamp,Sum]' --output table"
  description = "Command reading how often the rule matched at all. Zero after an upload means the event never arrived, which puts the problem in the trail rather than in the rule - check its logging status and its data resource selector"
}
