output "workspace_id" {
  value       = aws_prometheus_workspace.amp_workspace.id
  description = "The ws-<uuid> identifier. What every API call and every IAM condition actually references, unlike the alias"
}
output "workspace_arn" {
  value       = aws_prometheus_workspace.amp_workspace.arn
  description = "ARN of the workspace, for scoping a reader's or writer's IAM policy to this one workspace rather than the account"
}
output "alias" {
  value       = aws_prometheus_workspace.amp_workspace.alias
  description = "Human-readable name, which is what the console lists"
}
output "endpoint" {
  value       = aws_prometheus_workspace.amp_workspace.prometheus_endpoint
  description = "Base endpoint, ending in a slash. Grafana's data source URL is this value as-is; a remote write exporter needs api/v1/remote_write appended to it, which is why the two consumers get different outputs rather than both building a URL from this one"
}
output "remote_write_endpoint" {
  value       = "${aws_prometheus_workspace.amp_workspace.prometheus_endpoint}api/v1/remote_write"
  description = "Where a collector remote-writes. Assembled here rather than by the caller, because the base endpoint's trailing slash makes the concatenation easy to get wrong - and an exporter pointed at the base URL gets 404s that only appear in its own log (rules.md B-5)"
}
output "query_endpoint" {
  value       = "${aws_prometheus_workspace.amp_workspace.prometheus_endpoint}api/v1/query"
  description = "Where a query goes, for checking the workspace from the CLI without Grafana in the way"
}
output "rule_log_group" {
  value       = var.enable_rule_logging ? aws_cloudwatch_log_group.rule_logs[0].name : null
  description = "Log group AMP writes rule evaluation errors to, or null when rule logging is off"
}
output "query_log_group" {
  value       = var.enable_query_logging ? aws_cloudwatch_log_group.query_logs[0].name : null
  description = "Log group AMP writes served queries to, or null when query logging is off. The _monolithic template created this group and connected nothing to it"
}
output "series_count_command" {
  value       = "awscurl --service aps --region $(aws configure get region) '${aws_prometheus_workspace.amp_workspace.prometheus_endpoint}api/v1/query?query=count%28%7B__name__%3D~%22.%2B%22%7D%29'"
  description = "Counts every series in the workspace, which is the shortest answer to whether remote write is working. Needs awscurl because the endpoint requires SigV4 - a plain curl gets a 403 that looks like a permissions problem rather than an unsigned request"
}
output "logging_check_command" {
  value       = "aws amp describe-logging-configuration --workspace-id ${aws_prometheus_workspace.amp_workspace.id} ; aws amp describe-query-logging-configuration --workspace-id ${aws_prometheus_workspace.amp_workspace.id}"
  description = "Both logging configurations as AMP sees them. Worth reading once: the second one is what the _monolithic template silently omitted, and its absence looks identical to logging that has simply had nothing to report"
}
