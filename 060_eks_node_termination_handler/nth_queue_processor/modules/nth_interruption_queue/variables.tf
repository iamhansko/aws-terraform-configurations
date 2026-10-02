variable "name" {
  type        = string
  description = "Name of the queue, also used as the prefix for the EventBridge rule names. The _monolithic template left both unnamed, so the queue got a generated name and the five rules read as terraform-<hash> in the console - which is the opposite of useful when the question is whether a notice was delivered"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,80}$", var.name))
    error_message = "name must be 1-80 characters of letters, digits, hyphens and underscores."
  }
}
variable "message_retention_seconds" {
  type        = number
  default     = 300
  description = "How long an undelivered notice stays on the queue, five minutes as the _monolithic template had it. Deliberately short: an interruption notice is worthless after the instance is gone, and a long retention means the handler acts on nodes that no longer exist after an outage"

  validation {
    condition     = var.message_retention_seconds >= 60 && var.message_retention_seconds <= 1209600
    error_message = "message_retention_seconds must be between 60 and 1209600 (14 days)."
  }
}
variable "sqs_managed_sse_enabled" {
  type        = bool
  default     = true
  description = "Whether the queue is encrypted with the SQS-managed key. On, as the _monolithic template had it. SQS-managed rather than a customer KMS key, which would also require a key policy admitting EventBridge and a kms:Decrypt grant on the handler's role"
}
variable "enable_asg_termination_rule" {
  type        = bool
  default     = true
  description = "Whether to forward Auto Scaling terminate lifecycle actions. This is the rule that makes queue mode worth the extra infrastructure: an instance cannot learn from its own metadata that its Auto Scaling group has decided to replace it, so in IMDS mode a scale-in or an instance refresh takes the node without a drain. It pairs with the lifecycle hooks - the hook holds the instance in Terminating:Wait until the handler completes the action or the heartbeat expires"
}
variable "enable_scheduled_change_rule" {
  type        = bool
  default     = true
  description = "Whether to forward AWS Health scheduled change events - a planned instance retirement, typically days of notice rather than minutes"
}
variable "enable_spot_interruption_rule" {
  type        = bool
  default     = true
  description = "Whether to forward EC2 spot interruption warnings, the two-minute notice. IMDS mode sees these too; here they arrive centrally"
}
variable "enable_rebalance_rule" {
  type        = bool
  default     = true
  description = "Whether to forward EC2 rebalance recommendations. Weaker than an interruption warning - capacity at elevated risk, with no commitment that it will be reclaimed - which is why draining on them is a separate decision in the handler's configuration"
}
variable "enable_instance_state_change_rule" {
  type        = bool
  default     = true
  description = "Whether to forward EC2 instance state changes. The only signal for an instance stopped or terminated outright, where no warning is issued at all - and the noisiest rule of the five, since it fires for every state transition of every instance in the account"
}
variable "health_event_service_filter" {
  type        = list(string)
  default     = ["EC2"]
  description = "Services whose AWS Health events are forwarded. EC2 only, as the _monolithic template had it - without the filter the rule matches Health events for every service in the account and the handler is handed RDS and S3 notices it cannot act on. Empty list removes the filter"

  validation {
    condition     = alltrue([for service in var.health_event_service_filter : length(service) > 0])
    error_message = "health_event_service_filter must not contain empty service names."
  }
}
variable "health_event_type_categories" {
  type        = list(string)
  default     = ["scheduledChange"]
  description = "Health event categories forwarded, alongside the service filter. scheduledChange as the _monolithic template had it: the categories the handler can act on are the planned ones, and issue or accountNotification events describe things a drain does not help with"

  validation {
    condition     = length(var.health_event_type_categories) > 0 && alltrue([for category in var.health_event_type_categories : contains(["issue", "accountNotification", "scheduledChange", "investigation"], category)])
    error_message = "health_event_type_categories must be a non-empty subset of: issue, accountNotification, scheduledChange, investigation."
  }
}
