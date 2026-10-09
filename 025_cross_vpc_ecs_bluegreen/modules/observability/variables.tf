variable "dashboard_name" {
  type        = string
  description = "Name of the CloudWatch dashboard. Account wide, so a second copy of this project overwrites the first rather than failing"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,255}$", var.dashboard_name))
    error_message = "dashboard_name must be 1-255 characters of letters, digits, underscores and hyphens."
  }
}
variable "region" {
  type        = string
  description = "Region every widget queries. Passed in rather than read with a data source, which a module carrying depends_on would defer to apply (rules.md B-6, D-6)"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.region))
    error_message = "region must be an AWS region code (e.g. ap-northeast-2)."
  }
}
variable "account_id" {
  type        = string
  description = "Account ID. Needed because the flow log widget filters on the @log field, which is \"<account>:<log group>\" - the _monolithic template had a literal account number there, so that widget rendered empty in any other account"

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}
variable "load_balancer_arn_suffix" {
  type        = string
  description = "The app/<name>/<id> suffix of the application load balancer, which is the LoadBalancer dimension value for every AWS/ApplicationELB metric. Both alarms and the error widget are scoped to it - the _monolithic template left the alarms with an empty dimension map, which alarms on a metric that is never published"

  validation {
    condition     = can(regex("^app/", var.load_balancer_arn_suffix))
    error_message = "load_balancer_arn_suffix must be an application load balancer ARN suffix, starting with app/ - a net/ suffix belongs to a network load balancer, whose metrics are in the AWS/NetworkELB namespace and would make every widget here empty."
  }
}
variable "hub_vpc_name" {
  type        = string
  description = "Name of the hub VPC, used in the flow log widget title"

  validation {
    condition     = length(var.hub_vpc_name) > 0
    error_message = "hub_vpc_name must not be empty."
  }
}
variable "app_vpc_name" {
  type        = string
  description = "Name of the app VPC, used in the flow log widget title"

  validation {
    condition     = length(var.app_vpc_name) > 0
    error_message = "app_vpc_name must not be empty."
  }
}
variable "hub_flow_log_group_name" {
  type        = string
  description = "Hub VPC flow log group, taken from the network module rather than restated so the widget queries the group that exists (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_./#-]{1,512}$", var.hub_flow_log_group_name))
    error_message = "hub_flow_log_group_name must be 1-512 characters of letters, digits and the set _./#- that CloudWatch Logs accepts."
  }
}
variable "app_flow_log_group_name" {
  type        = string
  description = "App VPC flow log group"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_./#-]{1,512}$", var.app_flow_log_group_name))
    error_message = "app_flow_log_group_name must be 1-512 characters of letters, digits and the set _./#- that CloudWatch Logs accepts."
  }
}
variable "app_log_widgets" {
  type = map(object({
    log_group_name = string
    path_prefix    = string
  }))
  description = "One log widget per application stack, keyed by stack name. The _monolithic template wrote the two widgets out as literal JSON with the group names and the path patterns inline; this takes both from the stack modules, so a renamed log group cannot leave a widget querying a group that does not exist"

  validation {
    condition     = length(var.app_log_widgets) > 0
    error_message = "app_log_widgets must contain at least one stack."
  }
  validation {
    condition     = alltrue([for key in keys(var.app_log_widgets) : can(regex("^[a-z][a-z0-9_]*$", key))])
    error_message = "app_log_widgets keys become field names in a Logs Insights query (get_<key>, post_<key>), so each must start with a lowercase letter and contain only lowercase letters, digits and underscores."
  }
  validation {
    condition     = alltrue([for widget in values(var.app_log_widgets) : can(regex("^/", widget.path_prefix))])
    error_message = "app_log_widgets path_prefix values must start with '/'."
  }
}
variable "metric_period" {
  type        = number
  description = "Period in seconds for every widget. The _monolithic template used 60 throughout"

  validation {
    condition     = var.metric_period >= 1 && var.metric_period % 60 == 0 || contains([1, 5, 10, 30], var.metric_period)
    error_message = "metric_period must be 1, 5, 10, 30, or a multiple of 60."
  }
}
variable "high_utilization_annotation" {
  type        = number
  description = "Percentage the service CPU widget draws its horizontal annotation at"

  validation {
    condition     = var.high_utilization_annotation > 0 && var.high_utilization_annotation <= 100
    error_message = "high_utilization_annotation must be between 1 and 100."
  }
}
variable "alarm_period" {
  type        = number
  description = "Evaluation period in seconds for both alarms. The _monolithic template used 300, with the description saying \"within 5 minutes\" - so the period and the description are one value in intent and were two in the template"

  validation {
    condition     = contains([10, 30, 60, 300, 900, 3600, 21600, 86400], var.alarm_period) || var.alarm_period % 60 == 0
    error_message = "alarm_period must be 10, 30, or a multiple of 60 seconds."
  }
}
variable "alarm_evaluation_periods" {
  type        = number
  description = "Periods that must breach before an alarm fires"

  validation {
    condition     = var.alarm_evaluation_periods >= 1
    error_message = "alarm_evaluation_periods must be at least 1."
  }
}
variable "alarm_4xx_name" {
  type        = string
  description = "Name of the 4xx alarm. Account wide"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.alarm_4xx_name))
    error_message = "alarm_4xx_name must be 1-255 characters that CloudWatch accepts in an alarm name."
  }
}
variable "alarm_4xx_description" {
  type        = string
  description = "Description of the 4xx alarm"

  validation {
    condition     = length(var.alarm_4xx_description) > 0 && length(var.alarm_4xx_description) <= 1024
    error_message = "alarm_4xx_description must be between 1 and 1024 characters."
  }
}
variable "alarm_4xx_threshold" {
  type        = number
  description = "4xx responses in one period that trigger the alarm. Reachable by hand: a request to a path no listener rule matches returns the listener default 404"

  validation {
    condition     = var.alarm_4xx_threshold > 0
    error_message = "alarm_4xx_threshold must be greater than zero."
  }
}
variable "alarm_5xx_name" {
  type        = string
  description = "Name of the 5xx alarm. Account wide"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.alarm_5xx_name))
    error_message = "alarm_5xx_name must be 1-255 characters that CloudWatch accepts in an alarm name."
  }
}
variable "alarm_5xx_description" {
  type        = string
  description = "Description of the 5xx alarm"

  validation {
    condition     = length(var.alarm_5xx_description) > 0 && length(var.alarm_5xx_description) <= 1024
    error_message = "alarm_5xx_description must be between 1 and 1024 characters."
  }
}
variable "alarm_5xx_threshold" {
  type        = number
  description = "5xx responses in one period that trigger the alarm. Reachable by hand through the error path rule on the listener, which is what that rule is for"

  validation {
    condition     = var.alarm_5xx_threshold > 0
    error_message = "alarm_5xx_threshold must be greater than zero."
  }
}
