variable "aws_region" {
  type        = string
  description = "Region written into every OUTPUT block's region field. Fluent Bit runs inside the Fargate infrastructure and does not inherit a region from the caller, so it has to be named explicitly"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", var.aws_region))
    error_message = "aws_region must be a region code like ap-northeast-2."
  }
}
variable "pod_execution_role_name" {
  type        = string
  description = "Name of the Fargate pod execution IAM role the CloudWatch Logs policy is attached to. Fluent Bit writes as this role, not as anything the pod carries"

  validation {
    condition     = length(var.pod_execution_role_name) > 0
    error_message = "pod_execution_role_name must not be empty."
  }
}
variable "namespace" {
  type        = string
  default     = "aws-observability"
  description = "Namespace holding the logging ConfigMap. EKS looks for this exact name and ignores anything else, so it is a variable only to keep the value out of the resource body"

  validation {
    condition     = var.namespace == "aws-observability"
    error_message = "namespace must be aws-observability. EKS enables Fargate logging by looking for a namespace with that exact name carrying the aws-observability: enabled label; any other name is silently ignored and pods produce no logs."
  }
}
variable "configmap_name" {
  type        = string
  default     = "aws-logging"
  description = "Name of the logging ConfigMap. Like the namespace, EKS looks for this exact name"

  validation {
    condition     = var.configmap_name == "aws-logging"
    error_message = "configmap_name must be aws-logging - the only name the Fargate log router reads."
  }
}
variable "policy_name" {
  type        = string
  default     = "FargatePodExecutionCloudWatchLogsPolicy"
  description = "Name of the inline policy added to the pod execution role. The _monolithic template called this FargatePodExecutionFirehosePolicy in every variant including this one, which named the wrong sink"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,128}$", var.policy_name))
    error_message = "policy_name must be 1-128 characters from the set IAM accepts for a policy name."
  }
}
variable "log_sinks" {
  type = map(object({
    match          = string
    log_group_name = string
  }))
  default = {
    web = {
      match          = "app-web*"
      log_group_name = "/fargate/web"
    }
    stress = {
      match          = "app-stress*"
      log_group_name = "/fargate/stress"
    }
  }
  description = "One OUTPUT block per entry, keyed by a caller-chosen label. 'match' is matched against the tag the rewrite_tag filter builds from the pod's app label (app-<label>), so a pod labelled app=web matches app-web*. A pod whose app label matches no entry keeps its kube.* tag and its logs go nowhere"

  validation {
    condition     = length(var.log_sinks) > 0
    error_message = "log_sinks must contain at least one entry, otherwise Fluent Bit has nowhere to send anything and the ConfigMap silently drops every record."
  }
  validation {
    condition     = alltrue([for sink in values(var.log_sinks) : can(regex("^/[a-zA-Z0-9_./#-]+$", sink.log_group_name))])
    error_message = "log_sinks[*].log_group_name must be a valid CloudWatch log group name starting with '/'."
  }
  validation {
    condition     = alltrue([for sink in values(var.log_sinks) : length(sink.match) > 0])
    error_message = "log_sinks[*].match must not be empty - an OUTPUT block with no Match receives nothing."
  }
}
variable "log_stream_prefix" {
  type        = string
  default     = "from-fluent-bit-"
  description = "Prefix for the log stream names Fluent Bit creates inside each group"

  validation {
    condition     = length(var.log_stream_prefix) > 0
    error_message = "log_stream_prefix must not be empty."
  }
}
variable "log_retention_days" {
  type        = number
  default     = 60
  description = "Retention Fluent Bit sets on the groups it creates. Only meaningful while auto_create_group is true - Fluent Bit applies it with PutRetentionPolicy at creation and never revisits it"

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be one of the retention periods CloudWatch Logs accepts (1, 3, 5, 7, 14, 30, 60, 90, ... 3653)."
  }
}
variable "auto_create_group" {
  type        = bool
  default     = true
  description = "Whether Fluent Bit creates the log groups itself. True, as the _monolithic template had it, which is why the groups outlive terraform destroy - they are not Terraform resources. Set false only after declaring aws_cloudwatch_log_group resources, or logging fails with no group to write to"
}
variable "flb_log_cw" {
  type        = bool
  default     = false
  description = "Whether Fluent Bit ships its own process log to CloudWatch. Useful when the workload's logs never arrive and the question is whether Fluent Bit even started"
}
