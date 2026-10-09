output "dashboard_name" {
  value       = aws_cloudwatch_dashboard.dashboard.dashboard_name
  description = "Name of the dashboard"
}
output "dashboard_url" {
  value       = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${aws_cloudwatch_dashboard.dashboard.dashboard_name}"
  description = "Console URL of the dashboard, assembled from the region it was created in rather than left for a reader to navigate to"
}
output "alarm_names" {
  value       = [aws_cloudwatch_metric_alarm.load_balancer_4xx.alarm_name, aws_cloudwatch_metric_alarm.load_balancer_5xx.alarm_name]
  description = "Both alarm names"
}
output "alarm_state_command" {
  value       = "aws cloudwatch describe-alarms --alarm-names ${aws_cloudwatch_metric_alarm.load_balancer_4xx.alarm_name} ${aws_cloudwatch_metric_alarm.load_balancer_5xx.alarm_name} --query 'MetricAlarms[].[AlarmName,StateValue,StateReason]' --output table"
  description = "Command printing both alarms with their state. INSUFFICIENT_DATA for both no matter what the load balancer returns is the signature of the _monolithic template's empty dimension map - the dimension is set here, so a quiet period reads OK instead"
}
