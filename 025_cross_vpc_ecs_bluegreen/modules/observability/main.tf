locals {
  # The widget grid, built as a structure and encoded rather than written as a JSON heredoc.
  #
  # The _monolithic template had this as a 200 line heredoc of literal JSON, and that is where its
  # one hardcoded account number lived - a log widget filtering on "463470958750:/ws25/flow/hub",
  # which means the flow log comparison renders empty in any other account and nothing says why.
  # Encoding the structure means every identifier in it comes from a variable.
  #
  # Layout, matching the template's: the top row is the two VPCs' flow log comparison, then one log
  # widget per application stack, then service CPU. The second row is task CPU, container CPU and
  # the load balancer error counts. The per-stack widgets are generated, so a third stack lands at
  # x = 18 on the top row without the layout being rewritten.
  stack_keys = sort(keys(var.app_log_widgets))
  stack_log_widgets = [
    for index, key in local.stack_keys : {
      type   = "log"
      x      = 6 + index * 6
      y      = 0
      width  = 6
      height = 6
      properties = {
        region  = var.region
        title   = "GET ${var.app_log_widgets[key].path_prefix}, POST ${var.app_log_widgets[key].path_prefix}"
        view    = "timeSeries"
        stacked = false
        query = join("\n", [
          "SOURCE '${var.app_log_widgets[key].log_group_name}' | fields @message, @timestamp",
          "| stats ",
          "sum(if(@message like /GET \\${var.app_log_widgets[key].path_prefix}/, 1, 0)) as get_${key},",
          "sum(if(@message like /POST \\${var.app_log_widgets[key].path_prefix}/, 1, 0)) as post_${key}",
          "by bin(1m)",
        ])
      }
    }
  ]
  flow_log_widget = {
    type   = "log"
    x      = 0
    y      = 0
    width  = 6
    height = 6
    properties = {
      region  = var.region
      title   = "${var.hub_vpc_name}, ${var.app_vpc_name}"
      view    = "timeSeries"
      stacked = false
      # @log is "<account>:<log group>", which is why this widget needed the account number at all.
      # It comes from a variable now, so the widget works in whichever account it is applied to.
      query = join("\n", [
        "SOURCE '${var.app_flow_log_group_name}' | SOURCE '${var.hub_flow_log_group_name}' | fields @message, @timestamp, @LogGroup",
        "| filter @message like /ACCEPT/",
        "| stats ",
        "sum(if(@log = \"${var.account_id}:${var.hub_flow_log_group_name}\" , 1, 0)) as hub_vpc_accept,",
        "sum(if(@log = \"${var.account_id}:${var.app_flow_log_group_name}\", 1, 0)) as app_vpc_accept",
        "by bin(1m)",
      ])
    }
  }
  service_cpu_widget = {
    type   = "metric"
    x      = 18
    y      = 0
    width  = 6
    height = 6
    properties = {
      region   = var.region
      title    = "Top services by CPU utilization"
      period   = var.metric_period
      liveData = false
      legend = {
        position = "right"
      }
      timezone = "LOCAL"
      metrics = [
        [{ expression = "SELECT AVG(CPUUtilization) FROM SCHEMA(\"AWS/ECS\", ClusterName, ServiceName) GROUP BY ClusterName, ServiceName ORDER BY AVG() DESC LIMIT 10" }],
      ]
      annotations = {
        horizontal = [{
          value = var.high_utilization_annotation
          label = "High Utilization >="
        }]
      }
      yAxis = {
        left = {
          min       = 0
          showUnits = false
        }
      }
    }
  }
  # Both of these read the ECS/ContainerInsights namespace, which is only populated when the
  # cluster's containerInsights setting is "enhanced". On "enabled" they render as empty charts
  # rather than as an error, so the cluster setting and these widgets belong together.
  task_cpu_widget = {
    type   = "metric"
    x      = 0
    y      = 6
    width  = 6
    height = 6
    properties = {
      region   = var.region
      title    = "Top tasks by CPU utilization"
      period   = var.metric_period
      liveData = false
      legend = {
        position = "right"
      }
      timezone = "LOCAL"
      metrics = [
        [{ expression = "SELECT MAX(TaskCpuUtilization) FROM SCHEMA(\"ECS/ContainerInsights\", ClusterName, TaskDefinitionFamily, TaskId) GROUP BY ClusterName, TaskDefinitionFamily, TaskId ORDER BY MAX() DESC LIMIT 10" }],
      ]
      yAxis = {
        left = {
          min       = 0
          showUnits = false
        }
      }
    }
  }
  container_cpu_widget = {
    type   = "metric"
    x      = 6
    y      = 6
    width  = 6
    height = 6
    properties = {
      region   = var.region
      title    = "Top containers by CPU utilization"
      period   = var.metric_period
      liveData = false
      legend = {
        position = "right"
      }
      timezone = "LOCAL"
      metrics = [
        [{ expression = "SELECT MAX(ContainerCpuUtilization) FROM SCHEMA(\"ECS/ContainerInsights\", ClusterName, TaskDefinitionFamily, TaskId, ContainerName) GROUP BY ClusterName, TaskDefinitionFamily, TaskId, ContainerName ORDER BY MAX() DESC LIMIT 10" }],
      ]
      yAxis = {
        left = {
          min       = 0
          showUnits = false
        }
      }
    }
  }
  load_balancer_error_widget = {
    type   = "metric"
    x      = 12
    y      = 6
    width  = 6
    height = 6
    properties = {
      region = var.region
      title  = "HTTPCode_ELB_4XX_Count, HTTPCode_ELB_5XX_Count"
      period = var.metric_period
      stat   = "Sum"
      metrics = [
        ["AWS/ApplicationELB", "HTTPCode_ELB_4XX_Count", "LoadBalancer", var.load_balancer_arn_suffix, { region = var.region }],
        ["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", "LoadBalancer", var.load_balancer_arn_suffix, { region = var.region }],
      ]
    }
  }
  widgets = concat(
    [local.flow_log_widget],
    local.stack_log_widgets,
    [local.service_cpu_widget, local.task_cpu_widget, local.container_cpu_widget, local.load_balancer_error_widget],
  )
}
resource "aws_cloudwatch_dashboard" "dashboard" {
  dashboard_name = var.dashboard_name
  dashboard_body = jsonencode({
    widgets = local.widgets
  })
}
# The two alarms, each with the LoadBalancer dimension the _monolithic template left off.
#
# It declared "dimensions = {}" on both, and an empty dimension map is not "all load balancers
# aggregated" - AWS/ApplicationELB publishes HTTPCode_ELB_4XX_Count only with a LoadBalancer
# dimension, and there is no dimensionless aggregate to alarm on. So both alarms were created,
# both looked correct in the console, and both sat in INSUFFICIENT_DATA for the lifetime of the
# stack no matter how many 4xx or 5xx responses the load balancer returned. Nothing reports that:
# an alarm with no data is a normal state.
#
# treat_missing_data is explicit for the same reason. The default, "missing", means a period with
# no requests at all leaves the alarm in its previous state rather than resetting it - which during
# a demo reads as a stuck alarm. notBreaching makes a quiet period an OK.
resource "aws_cloudwatch_metric_alarm" "load_balancer_4xx" {
  alarm_name        = var.alarm_4xx_name
  alarm_description = var.alarm_4xx_description
  namespace         = "AWS/ApplicationELB"
  metric_name       = "HTTPCode_ELB_4XX_Count"
  dimensions = {
    LoadBalancer = var.load_balancer_arn_suffix
  }
  statistic           = "Sum"
  period              = var.alarm_period
  evaluation_periods  = var.alarm_evaluation_periods
  threshold           = var.alarm_4xx_threshold
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
}
resource "aws_cloudwatch_metric_alarm" "load_balancer_5xx" {
  alarm_name        = var.alarm_5xx_name
  alarm_description = var.alarm_5xx_description
  namespace         = "AWS/ApplicationELB"
  metric_name       = "HTTPCode_ELB_5XX_Count"
  dimensions = {
    LoadBalancer = var.load_balancer_arn_suffix
  }
  statistic           = "Sum"
  period              = var.alarm_period
  evaluation_periods  = var.alarm_evaluation_periods
  threshold           = var.alarm_5xx_threshold
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
}
