variable "name" {
  type        = string
  description = "Name of the ECS cluster"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,255}$", var.name))
    error_message = "name must be 1-255 characters of letters, digits, hyphens and underscores."
  }
}
variable "container_insights" {
  type        = string
  default     = "enhanced"
  description = "Container Insights level, as the _monolithic template had it. enhanced adds per-task and per-container metrics and is billed per metric"

  validation {
    condition     = contains(["enhanced", "enabled", "disabled"], var.container_insights)
    error_message = "container_insights must be enhanced, enabled or disabled."
  }
}
