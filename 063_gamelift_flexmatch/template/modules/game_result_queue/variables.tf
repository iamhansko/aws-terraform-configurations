variable "name" {
  type        = string
  description = "Queue name. Nothing hard-codes it: the game server reads the queue URL out of the config.ini baked into server.zip, and game-sqs-process is driven by an event source mapping"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,80}$", var.name))
    error_message = "name must be 1-80 characters of letters, digits, hyphens and underscores (a standard queue, so no .fifo suffix)."
  }
}
variable "visibility_timeout_seconds" {
  type        = number
  default     = 60
  description = "Visibility timeout, as the _monolithic template had it. Lambda refuses an SQS event source mapping whose queue timeout is shorter than the function's, which the root checks"

  validation {
    condition     = var.visibility_timeout_seconds >= 0 && var.visibility_timeout_seconds <= 43200
    error_message = "visibility_timeout_seconds must be between 0 and 43200."
  }
}
