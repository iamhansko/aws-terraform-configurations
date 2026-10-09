variable "log_group_name" {
  type        = string
  default     = "queue-log-group"
  description = <<-DESC
    Name of the log group, as the _monolithic template named it.

    This name is not only Terraform's. The CloudWatch agent on the worker instance is configured with the same
    string, and an agent writing to a group that does not exist creates it - with no retention and outside
    Terraform's state. That is why the root orders the worker instance after this module: the group has to
    exist before the agent starts, or the apply can lose a race with it and fail with
    ResourceAlreadyExistsException (rules.md D-2).
  DESC

  validation {
    condition     = can(regex("^[a-zA-Z0-9_./#-]{1,512}$", var.log_group_name))
    error_message = "log_group_name must be 1-512 characters of letters, digits and the characters _ . / # - that CloudWatch Logs allows in a group name."
  }
}
variable "retention_in_days" {
  type        = number
  default     = 14
  description = "How long log events are kept. The _monolithic template set no retention, which means never expire: the worker writes one line per message processed, so a load run of twenty thousand messages is twenty thousand lines kept and billed forever, and terraform destroy of the original left the group behind because the group it created was the agent's, not Terraform's"

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.retention_in_days)
    error_message = "retention_in_days must be one of the retention periods CloudWatch Logs accepts."
  }
}
variable "filter_name" {
  type        = string
  default     = "queue-filter"
  description = "Name of the metric filter, as the _monolithic template named it"

  validation {
    condition     = length(var.filter_name) > 0 && length(var.filter_name) <= 512
    error_message = "filter_name must be 1-512 characters."
  }
}
variable "filter_pattern" {
  type        = string
  default     = "\"처리성공\""
  description = <<-DESC
    What counts as a processed message. The worker writes the Korean word 처리성공 ("processing succeeded") on
    every message it deletes, and this pattern counts those lines.

    The inner quotes are part of the pattern and not decoration. An unquoted CloudWatch filter term is matched
    as a token against alphanumeric word boundaries, which does not work for non-ASCII text; quoting it makes
    it an exact substring match. Writing it unquoted is not an error - the filter is created, matches nothing,
    and the metric simply never has a datapoint, which looks identical to a worker that is not running.
  DESC

  validation {
    condition     = length(var.filter_pattern) > 0
    error_message = "filter_pattern must not be empty. An empty pattern matches every log event, which would count the worker's error lines as successes."
  }
}
variable "metric_name" {
  type        = string
  default     = "queue-metric"
  description = "Name of the metric the filter publishes, as the _monolithic template named it"

  validation {
    condition     = length(var.metric_name) > 0 && length(var.metric_name) <= 255
    error_message = "metric_name must be 1-255 characters."
  }
}
variable "metric_namespace" {
  type        = string
  default     = "queue"
  description = "Namespace the metric is published under. A custom namespace rather than an AWS/* one, which is required - CloudWatch reserves the AWS/ prefix and rejects a filter that tries to publish into it"

  validation {
    condition     = length(var.metric_namespace) > 0 && !startswith(var.metric_namespace, "AWS/")
    error_message = "metric_namespace must not be empty and must not start with AWS/, which CloudWatch reserves for its own metrics."
  }
}
variable "metric_value" {
  type        = string
  default     = "1"
  description = "Value published per matching log event. \"1\" counts events, as the _monolithic template had it. A string rather than a number because the attribute also accepts a field reference like $.size, which is why the provider types it as a string"

  validation {
    condition     = length(var.metric_value) > 0
    error_message = "metric_value must not be empty."
  }
}
variable "metric_window_minutes" {
  type        = number
  default     = 30
  description = "How far back the verification commands this module exposes look"

  validation {
    condition     = var.metric_window_minutes >= 1
    error_message = "metric_window_minutes must be at least 1."
  }
}
variable "log_stream_prefix" {
  type        = string
  default     = null
  description = "Optional stream name prefix for the tail command this module exposes. Null tails every stream, which is what is wanted here: the agent names its stream after the instance id, so filtering by name would mean knowing that id before the instance exists"

  validation {
    condition     = var.log_stream_prefix == null || length(var.log_stream_prefix) > 0
    error_message = "log_stream_prefix must be a non-empty string, or null to tail every stream."
  }
}
