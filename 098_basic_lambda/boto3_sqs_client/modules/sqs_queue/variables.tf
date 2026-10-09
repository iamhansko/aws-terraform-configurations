variable "name" {
  type        = string
  default     = "queue"
  description = "Name of the queue, as the _monolithic template named it. A fixed name, so two copies of this project in one region collide with QueueAlreadyExists - which is the honest trade for a name that appears in the worker script, the outputs and the console"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,80}$", var.name)) && !endswith(var.name, ".fifo")
    error_message = "name must be 1-80 characters of letters, digits, hyphens and underscores. A .fifo suffix is rejected here because a FIFO queue also requires fifo_queue = true and a message group id on every send, neither of which this project's Lambda handler provides."
  }
}
variable "message_retention_seconds" {
  type        = number
  default     = 3600
  description = "How long an unconsumed message survives, as the _monolithic template set it. One hour rather than the four-day default, which matters for this demo: the load generator can put tens of thousands of messages on the queue, and if nobody starts the worker they are billed as stored messages until they expire"

  validation {
    condition     = var.message_retention_seconds >= 60 && var.message_retention_seconds <= 1209600
    error_message = "message_retention_seconds must be between 60 and 1209600 (14 days) - the range SQS accepts."
  }
}
variable "visibility_timeout_seconds" {
  type        = number
  default     = 30
  description = "How long a received message stays hidden from other consumers. 30 seconds is both SQS's default and the value the worker script passes on each receive_message call, so it is stated here to keep the two from disagreeing silently - a per-call value shorter than the time the worker takes to delete the message means the message comes back and is processed twice"

  validation {
    condition     = var.visibility_timeout_seconds >= 0 && var.visibility_timeout_seconds <= 43200
    error_message = "visibility_timeout_seconds must be between 0 and 43200 (12 hours) - the range SQS accepts."
  }
}
variable "sqs_managed_sse_enabled" {
  type        = bool
  default     = true
  description = "Whether SQS encrypts messages at rest with its own managed key. True, which is also what SQS does for a queue created without the attribute, so this restates the _monolithic behaviour rather than changing it. It is spelled out because the messages here stand in for application payloads"
}
