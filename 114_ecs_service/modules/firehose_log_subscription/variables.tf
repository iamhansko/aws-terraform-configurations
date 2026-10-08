variable "log_group_name" {
  type        = string
  default     = "/ecs/task/container/logs"
  description = "Name of the log group the containers write to, as the _monolithic template had it. A literal path, so two copies of this project in one account collide on it at apply with ResourceAlreadyExistsException - pass a project-specific name to avoid that"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_./#-]{1,512}$", var.log_group_name))
    error_message = "log_group_name must be 1-512 characters of letters, digits and _ . / # -."
  }
}
variable "retention_in_days" {
  type        = number
  default     = null
  description = "Days CloudWatch keeps the events. Null keeps them forever, which is what the _monolithic template did by not setting it - the copy in S3 is the long-term one, so a short retention here is a reasonable change"

  validation {
    condition     = var.retention_in_days == null || contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], coalesce(var.retention_in_days, 1))
    error_message = "retention_in_days must be one of the values CloudWatch Logs accepts (1, 3, 5, 7, 14, 30, 60, 90, ...), or null to keep events forever."
  }
}
variable "role_name_prefix" {
  type        = string
  default     = "cwlogs-to-firehose-"
  description = "Prefix for the generated name of the role CloudWatch Logs assumes to write into Firehose"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,38}$", var.role_name_prefix))
    error_message = "role_name_prefix must be 1-38 characters from the set IAM accepts for a role name."
  }
}
variable "filter_name" {
  type        = string
  default     = "firehose-subscription-filter"
  description = "Name of the subscription filter, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[^:*]{1,512}$", var.filter_name))
    error_message = "filter_name must be 1-512 characters and contain no colon or asterisk."
  }
}
variable "filter_pattern" {
  type        = string
  default     = ""
  description = "Which events are streamed. Empty matches every event, as the _monolithic template had it"

  validation {
    condition     = length(var.filter_pattern) <= 1024
    error_message = "filter_pattern must be 1024 characters or fewer."
  }
}
variable "delivery_stream_arn" {
  type        = string
  description = "ARN of the Firehose delivery stream the events are sent to. Passed in from the module that owns the stream (rules.md B-6)"

  validation {
    condition     = can(regex("^arn:aws[a-zA-Z-]*:firehose:[a-z0-9-]+:[0-9]{12}:deliverystream/.+$", var.delivery_stream_arn))
    error_message = "delivery_stream_arn must be a Firehose delivery stream ARN."
  }
}
variable "delivery_stream_kms_key_arn" {
  type        = string
  description = "ARN of the KMS key the delivery stream encrypts with. The subscription role is granted data-key use on this key only"

  validation {
    condition     = can(regex("^arn:aws[a-zA-Z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/.+$", var.delivery_stream_kms_key_arn))
    error_message = "delivery_stream_kms_key_arn must be a KMS key ARN."
  }
}
