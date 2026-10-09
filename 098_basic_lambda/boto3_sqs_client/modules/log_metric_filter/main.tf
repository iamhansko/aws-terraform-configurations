# The measurement end of the project: the worker writes a line per processed message, the agent ships it
# here, and the filter turns those lines into a CloudWatch metric.
#
# The group and the filter are one module because a filter without its group is not expressible - the filter
# names a group, and CloudWatch rejects a filter on a group that does not exist - while a group without a
# filter would collect the lines and count nothing.
resource "aws_cloudwatch_log_group" "queue" {
  name              = var.log_group_name
  retention_in_days = var.retention_in_days
}
resource "aws_cloudwatch_log_metric_filter" "queue" {
  name           = var.filter_name
  pattern        = var.filter_pattern
  log_group_name = aws_cloudwatch_log_group.queue.name

  # False, as the _monolithic template set it, and also the provider's default - stated because the
  # alternative changes what the pattern is matched against. With transformation applied, the filter sees the
  # structured output of a log transformer rather than the raw line, and this pattern matches a raw line.
  apply_on_transformed_logs = false

  metric_transformation {
    name      = var.metric_name
    namespace = var.metric_namespace
    value     = var.metric_value
    # Deliberately no default_value. With one set, the filter publishes a zero for every evaluation period in
    # which nothing matched, which makes "the worker is not running" and "the worker is running and finding
    # nothing" look the same on a graph. Without it, a period with no match has no datapoint at all, and the
    # absence is the signal.
  }
}
