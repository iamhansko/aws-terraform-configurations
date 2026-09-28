# The Amazon Managed Prometheus workspace the collector remote-writes into, and the two
# log groups AMP itself reports through.
#
# The workspace is the simple part. What the _monolithic template got wrong is on either
# side of it: the query logging configuration was left as a commented-out block because
# cfn2tf could not map it, and both log groups were created under /aws/amp with no retention
# and no resource policy - so one of them was never connected to anything and neither could
# have been written to.
# Rule evaluation errors. A recording or alerting rule that fails has no other symptom: the
# workspace simply has no series for it.
resource "aws_cloudwatch_log_group" "rule_logs" {
  count = var.enable_rule_logging ? 1 : 0

  name = "${var.log_group_prefix}/${var.alias}/rules"
  # 0 is not a value CloudWatch accepts; null is how "never expire" is expressed.
  retention_in_days = var.log_retention_days == 0 ? null : var.log_retention_days
}
resource "aws_prometheus_workspace" "amp_workspace" {
  alias = var.alias

  # Rule logging is an inline block on the workspace, while query logging below is a separate
  # resource. The asymmetry is the provider's, not a choice here - there is no
  # aws_prometheus_logging_configuration resource, so a dynamic block is how this is made
  # optional.
  dynamic "logging_configuration" {
    for_each = var.enable_rule_logging ? [1] : []

    content {
      # The ARN AMP wants ends in :* - it addresses the group and its streams, and the
      # provider's .arn attribute stops at the group.
      log_group_arn = "${aws_cloudwatch_log_group.rule_logs[0].arn}:*"
    }
  }
}
# The queries AMP served. This is the half the _monolithic template lost: its log group was
# created and nothing pointed at it.
resource "aws_cloudwatch_log_group" "query_logs" {
  count = var.enable_query_logging ? 1 : 0

  name              = "${var.log_group_prefix}/${var.alias}/queries"
  retention_in_days = var.log_retention_days == 0 ? null : var.log_retention_days
}
resource "aws_prometheus_query_logging_configuration" "amp_workspace" {
  count = var.enable_query_logging ? 1 : 0

  workspace_id = aws_prometheus_workspace.amp_workspace.id

  destination {
    cloudwatch_logs {
      log_group_arn = "${aws_cloudwatch_log_group.query_logs[0].arn}:*"
    }
    filters {
      # Zero logs every query. See var.query_logging_qsp_threshold.
      qsp_threshold = var.query_logging_qsp_threshold
    }
  }
}
