variable "queue_name" {
  type        = string
  default     = "game-result-queue"
  description = "Name of the queue, as the _monolithic template had it. Unique per account and region. Not load-bearing: the game server reads the queue URL from the config.ini the userdata writes, not the name"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,80}$", var.queue_name))
    error_message = "queue_name must be 1-80 characters of letters, digits, hyphens and underscores (a standard queue, so no .fifo suffix)."
  }
}
variable "visibility_timeout_seconds" {
  type        = number
  default     = 60
  description = "Visibility timeout of the queue, as the _monolithic template had it. Must be at least the timeout of the function that consumes it"

  validation {
    condition     = var.visibility_timeout_seconds >= 0 && var.visibility_timeout_seconds <= 43200
    error_message = "visibility_timeout_seconds must be between 0 and 43200 (12 hours)."
  }
}
