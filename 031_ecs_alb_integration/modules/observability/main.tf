# The dashboard and the 5xx alarm - the two things this project exists to show.
locals {
  # The window the alarm actually covers, and the description derived from it.
  #
  # The _monolithic template wrote the description as a fixed sentence next to the numbers it described
  # ("5xx 에러가 2번 이상 발생했습니다." against threshold = 2 and period = 300). Changing a threshold left
  # the sentence wrong and nothing said so, which is the usual fate of prose that restates a value. Derived
  # here instead, so the alarm's own description and its configuration cannot disagree.
  alarm_window_minutes = var.alarm_period * var.alarm_evaluation_periods / 60
  alarm_description    = "Fires when ${var.load_balancer_name} returns ${var.alarm_threshold} or more ${var.alarm_metric_name} responses within ${local.alarm_window_minutes} minutes"

  # The widget grid, built as a structure and encoded rather than written as a heredoc of literal JSON.
  #
  # The _monolithic template had it as a JSON heredoc with interpolations spliced into it, which works and
  # has one cost: a mistyped key is accepted by the API and renders as an empty chart. Encoding a structure
  # means every identifier in it comes from a variable and the JSON itself is generated.
  #
  # The second entry in each metrics list is written out in full. CloudFormation's original used the "."
  # shorthand ([ ".", "MemoryUtilization", ".", ".", ".", "." ]), which CloudWatch expands to "same as the
  # entry above" - correct, and only readable by counting positions against the line above it.
  ecs_widget = {
    type   = "metric"
    x      = 0
    y      = 0
    width  = 8
    height = 7
    properties = {
      period = var.metric_period
      stat   = "Average"
      title  = "ECS CPU/Memory Usage"
      region = var.region
      metrics = [
        ["AWS/ECS", "CPUUtilization", "ClusterName", var.cluster_name, "ServiceName", var.service_name],
        ["AWS/ECS", "MemoryUtilization", "ClusterName", var.cluster_name, "ServiceName", var.service_name],
      ]
    }
  }
  load_balancer_widget = {
    type   = "metric"
    x      = 8
    y      = 0
    width  = 8
    height = 7
    properties = {
      period = var.metric_period
      stat   = "Sum"
      title  = "ALB Requests & 5xx Errors"
      region = var.region
      metrics = [
        ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.load_balancer_arn_suffix],
        ["AWS/ApplicationELB", var.alarm_metric_name, "LoadBalancer", var.load_balancer_arn_suffix],
      ]
    }
  }
}
resource "aws_cloudwatch_dashboard" "dashboard" {
  dashboard_name = var.dashboard_name
  dashboard_body = jsonencode({
    widgets = [local.ecs_widget, local.load_balancer_widget]
  })
}
resource "aws_cloudwatch_metric_alarm" "load_balancer_5xx" {
  alarm_name        = var.alarm_name
  alarm_description = local.alarm_description
  namespace         = "AWS/ApplicationELB"
  metric_name       = var.alarm_metric_name
  # The dimension the _monolithic template left off.
  #
  # It declared "dimensions = {}", and an empty dimension map is not "every load balancer aggregated".
  # AWS/ApplicationELB publishes HTTPCode_Target_5XX_Count only against a LoadBalancer dimension - there is
  # no dimensionless variant of it - so the alarm was created, looked right in the console, and sat in
  # INSUFFICIENT_DATA for the life of the stack no matter how many 5xx the load balancer returned. Nothing
  # reports that: an alarm with no data is a normal state, and this one had a reason to be quiet.
  #
  # The dashboard widget directly above it in the same template was already correct, using
  # aws_lb.alb.arn_suffix - so the chart filled in while the alarm on the same metric never moved. That
  # pairing is what makes the omission hard to notice and worth a note here.
  dimensions = {
    LoadBalancer = var.load_balancer_arn_suffix
  }
  statistic           = "Sum"
  period              = var.alarm_period
  evaluation_periods  = var.alarm_evaluation_periods
  threshold           = var.alarm_threshold
  comparison_operator = "GreaterThanOrEqualToThreshold"
  # Derived rather than set, which is the whole point of it being derived.
  #
  # The _monolithic template had actions_enabled = true and no alarm_actions. That combination is accepted
  # by CloudWatch and means nothing: the alarm transitions to ALARM and notifies nobody, while reading as
  # though notification had been configured. Nothing here creates an SNS topic - that would be an addition
  # to the original, and a demo topic needs a subscription a person has to confirm out of band before it
  # delivers anything - so the honest configuration is actions_enabled = false.
  #
  # Writing it as a function of the list rather than as its own variable makes the misleading combination
  # inexpressible: a caller who passes a topic ARN gets the actions enabled, and a caller who passes nothing
  # cannot accidentally claim they are (rules.md B-1).
  actions_enabled = length(var.alarm_actions) > 0
  alarm_actions   = var.alarm_actions
  # Explicit, as the original had it, and worth keeping: the default ("missing") leaves a period with no
  # requests at all in the previous state rather than resetting it, which during a demo reads as a stuck
  # alarm. notBreaching makes a quiet period an OK.
  treat_missing_data = "notBreaching"
}
