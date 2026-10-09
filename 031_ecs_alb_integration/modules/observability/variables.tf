variable "region" {
  type        = string
  description = "Region the widgets read their metrics from. Passed in rather than read here, so this module takes a region string and the caller decides where it came from (rules.md B-6)"

  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.region))
    error_message = "region must be a region code such as ap-northeast-2."
  }
}
variable "dashboard_name" {
  type        = string
  description = "Name of the dashboard"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,255}$", var.dashboard_name))
    error_message = "dashboard_name must be 1-255 characters of letters, digits, underscores and hyphens."
  }
}
variable "cluster_name" {
  type        = string
  description = "ClusterName dimension of the ECS widget"

  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "cluster_name must not be empty."
  }
}
variable "service_name" {
  type        = string
  description = "ServiceName dimension of the ECS widget"

  validation {
    condition     = length(var.service_name) > 0
    error_message = "service_name must not be empty."
  }
}
variable "load_balancer_name" {
  type        = string
  description = "Name of the load balancer, used only in the alarm description so that a person reading it in the console knows which load balancer is meant"

  validation {
    condition     = length(var.load_balancer_name) > 0
    error_message = "load_balancer_name must not be empty."
  }
}
variable "load_balancer_arn_suffix" {
  type        = string
  description = "LoadBalancer dimension of the ALB widget and of the alarm: the app/<name>/<id> portion of the ARN. Taken from the load balancer module rather than parsed out of its ARN here (rules.md B-5)"

  validation {
    condition     = can(regex("^app/", var.load_balancer_arn_suffix))
    error_message = "load_balancer_arn_suffix must be the arn_suffix of an application load balancer, which begins with app/ - a net/ value belongs to a network load balancer, whose metrics are in the AWS/NetworkELB namespace rather than AWS/ApplicationELB."
  }
}
variable "metric_period" {
  type        = number
  default     = 60
  description = "Resolution of the dashboard widgets in seconds"

  validation {
    condition     = contains([1, 5, 10, 30, 60, 300, 900, 3600], var.metric_period)
    error_message = "metric_period must be 1, 5, 10, 30, 60, 300, 900 or 3600 seconds."
  }
}
variable "alarm_name" {
  type        = string
  description = "Name of the alarm"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_.:/#-]{1,255}$", var.alarm_name))
    error_message = "alarm_name must be 1-255 characters of letters, digits and _ . : / # -."
  }
}
variable "alarm_metric_name" {
  type        = string
  default     = "HTTPCode_Target_5XX_Count"
  description = "AWS/ApplicationELB metric the alarm watches, and the second series on the ALB widget. Target rather than ELB, as the _monolithic template had it: Target counts the responses the application produced, ELB counts the ones the load balancer generated on its own when it could not reach a target"

  validation {
    condition     = contains(["HTTPCode_Target_5XX_Count", "HTTPCode_Target_4XX_Count", "HTTPCode_ELB_5XX_Count", "HTTPCode_ELB_4XX_Count"], var.alarm_metric_name)
    error_message = "alarm_metric_name must be one of the AWS/ApplicationELB response-code metrics that are published against a LoadBalancer dimension: HTTPCode_Target_5XX_Count, HTTPCode_Target_4XX_Count, HTTPCode_ELB_5XX_Count or HTTPCode_ELB_4XX_Count."
  }
}
variable "alarm_threshold" {
  type        = number
  default     = 2
  description = "Count in one period that puts the alarm into ALARM"

  validation {
    condition     = var.alarm_threshold > 0
    error_message = "alarm_threshold must be greater than zero."
  }
}
variable "alarm_period" {
  type        = number
  default     = 300
  description = "Length of each evaluation period in seconds"

  validation {
    condition     = contains([10, 20, 30, 60, 300, 900, 3600], var.alarm_period)
    error_message = "alarm_period must be 10, 20, 30, 60, 300, 900 or 3600 seconds, the resolutions CloudWatch accepts for a metric alarm."
  }
}
variable "alarm_evaluation_periods" {
  type        = number
  default     = 1
  description = "Consecutive periods that must breach before the alarm fires"

  validation {
    condition     = var.alarm_evaluation_periods >= 1
    error_message = "alarm_evaluation_periods must be at least 1."
  }
}
variable "alarm_actions" {
  type        = list(string)
  default     = []
  description = "ARNs notified on the transition into ALARM. Empty leaves actions_enabled false, which is the accurate description of an alarm with nothing attached - see main.tf"

  validation {
    condition     = alltrue([for arn in var.alarm_actions : can(regex("^arn:aws(-[a-z]+)*:", arn))])
    error_message = "alarm_actions must contain ARNs."
  }
}
