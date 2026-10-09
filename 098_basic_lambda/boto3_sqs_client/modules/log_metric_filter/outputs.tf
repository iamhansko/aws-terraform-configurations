output "log_group_name" {
  value       = aws_cloudwatch_log_group.queue.name
  description = "Name of the log group, read back off the resource. This is the value the worker instance's CloudWatch agent configuration has to carry, and the root passes this output into that module rather than the variable, so the two cannot drift (rules.md B-5)"
}
output "log_group_arn" {
  value       = aws_cloudwatch_log_group.queue.arn
  description = "ARN of the log group, for narrowing an agent's IAM policy to this group alone"
}
output "metric_name" {
  value       = aws_cloudwatch_log_metric_filter.queue.metric_transformation[0].name
  description = "Name of the published metric"
}
output "metric_namespace" {
  value       = aws_cloudwatch_log_metric_filter.queue.metric_transformation[0].namespace
  description = "Namespace of the published metric"
}
output "filter_pattern" {
  value       = aws_cloudwatch_log_metric_filter.queue.pattern
  description = "The pattern as CloudWatch stored it, quotes included. Worth printing: a pattern that lost its quotes is created successfully and matches nothing"
}
output "metric_statistics_command" {
  value       = <<-CMD
    aws cloudwatch get-metric-statistics --namespace ${var.metric_namespace} --metric-name ${var.metric_name} --start-time $(date -u -d '-${var.metric_window_minutes} minutes' +%Y-%m-%dT%H:%M:%SZ) --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) --period 60 --statistics Sum --output table
  CMD
  description = "How many messages the worker has reported processing. Whether the filter has ever matched is not a resource attribute and Terraform cannot know it, so this is a command (rules.md H-2). An empty Datapoints list has three possible causes in order of likelihood: the worker is not running, the agent is not shipping, or the pattern lost its quotes"
}
output "log_tail_command" {
  value       = "aws logs tail ${aws_cloudwatch_log_group.queue.name} --since ${var.metric_window_minutes}m --format short${var.log_stream_prefix == null ? "" : " --log-stream-name-prefix ${var.log_stream_prefix}"}"
  description = "The raw lines behind the metric. Run this before trusting an empty metric: lines present here with no datapoint isolates the fault to the filter pattern, and no lines at all points at the worker or the agent"
}
output "agent_status_command" {
  value       = "sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a status"
  description = "Run on the worker instance itself. The agent reports \"stopped\" when fetch-config failed during cloud-init, which is the usual reason the log group stays empty while the worker is clearly running"
}
