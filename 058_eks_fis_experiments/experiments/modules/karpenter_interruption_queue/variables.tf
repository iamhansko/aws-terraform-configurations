variable "name" {
  type        = string
  description = "Name of the SQS queue. Karpenter's chart is given this same value as settings.interruptionQueue, so the two have to agree - a controller pointed at a queue that does not exist logs an error on every poll and otherwise behaves as though interruption handling were switched off (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,80}$", var.name))
    error_message = "name must be 1-80 characters of letters, digits, hyphens and underscores - the character set SQS accepts for a standard queue name."
  }
}
variable "message_retention_seconds" {
  type        = number
  default     = 300
  description = "How long an unread interruption notice stays in the queue, five minutes as the _monolithic template had it. Short on purpose: a spot interruption warning gives two minutes' notice, so a notice older than that describes an instance that is already gone and acting on it would drain a node that no longer exists"

  validation {
    condition     = var.message_retention_seconds >= 60 && var.message_retention_seconds <= 1209600
    error_message = "message_retention_seconds must be between 60 and 1209600 (14 days)."
  }
}
variable "sqs_managed_sse_enabled" {
  type        = bool
  default     = true
  description = "Whether SQS encrypts messages with keys it manages. True, and free - the alternative is a KMS key whose policy has to admit both EventBridge and Karpenter's role"
}
variable "enable_scheduled_change_rule" {
  type        = bool
  default     = true
  description = "Whether AWS Health scheduled change events are routed to the queue. These are the notices for planned retirement and maintenance of an instance - the slowest-moving of the four, and the only one that gives days rather than minutes"
}
variable "enable_spot_interruption_rule" {
  type        = bool
  default     = true
  description = "Whether EC2 spot interruption warnings are routed to the queue. This is the one the FIS spot interruption experiment produces, so turning it off makes that experiment run successfully and change nothing observable"
}
variable "enable_rebalance_rule" {
  type        = bool
  default     = true
  description = "Whether EC2 rebalance recommendations are routed to the queue. A weaker signal than an interruption warning - it says capacity is at elevated risk rather than that this instance is going - so acting on it trades some churn for fewer hard interruptions"
}
variable "enable_instance_state_change_rule" {
  type        = bool
  default     = true
  description = "Whether EC2 instance state change notifications are routed to the queue. This is what the FIS stop-instances experiment produces: no interruption warning is issued for an instance that is simply stopped, so without this rule Karpenter learns about it only when the node stops sending heartbeats"
}
variable "health_event_service_filter" {
  type        = list(string)
  default     = ["EC2"]
  description = "Which AWS Health events reach the queue, by service. The _monolithic template matched every AWS Health Event with no filter at all, which sends the queue notices about services this cluster has nothing to do with - Karpenter ignores them, so the cost is queue traffic rather than incorrect behaviour. Empty disables the filter and restores that behaviour"

  validation {
    condition     = alltrue([for s in var.health_event_service_filter : length(s) > 0])
    error_message = "health_event_service_filter must not contain empty strings."
  }
}
