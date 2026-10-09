output "dashboard_name" {
  value       = aws_cloudwatch_dashboard.dashboard.dashboard_name
  description = "Name of the dashboard"
}
output "dashboard_url" {
  value       = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${aws_cloudwatch_dashboard.dashboard.dashboard_name}"
  description = "Console URL of the dashboard, assembled from the region it was created in rather than left for a reader to navigate to"
}
output "alarm_name" {
  value       = aws_cloudwatch_metric_alarm.load_balancer_5xx.alarm_name
  description = "Name of the 5xx alarm"
}
output "alarm_state_command" {
  value       = "aws cloudwatch describe-alarms --alarm-names ${aws_cloudwatch_metric_alarm.load_balancer_5xx.alarm_name} --query 'MetricAlarms[].[AlarmName,StateValue,StateReason]' --output table"
  description = "The alarm with its state and the reason for it. INSUFFICIENT_DATA no matter what the load balancer returns is the signature of the _monolithic template's empty dimension map; with the dimension set, a quiet period reads OK and five hundreds inside one period read ALARM"
}
output "actions_enabled" {
  value       = aws_cloudwatch_metric_alarm.load_balancer_5xx.actions_enabled
  description = "Whether the alarm has anywhere to notify. False unless alarm_actions was given something, which is the state the _monolithic template was in while claiming the opposite (rules.md B-5)"
}
