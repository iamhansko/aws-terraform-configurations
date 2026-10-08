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
variable "execute_command_logging" {
  type        = string
  default     = "DEFAULT"
  description = "Where ECS Exec session output is logged. DEFAULT, as the _monolithic template had it, uses the task definition's awslogs configuration"

  validation {
    condition     = contains(["NONE", "DEFAULT", "OVERRIDE"], var.execute_command_logging)
    error_message = "execute_command_logging must be NONE, DEFAULT or OVERRIDE."
  }
}
variable "capacity_providers" {
  type        = list(string)
  default     = ["FARGATE", "FARGATE_SPOT"]
  description = "Capacity providers attached to the cluster, as the _monolithic template had them"

  validation {
    condition     = length(setsubtract(var.capacity_providers, ["FARGATE", "FARGATE_SPOT"])) == 0
    error_message = "capacity_providers may contain only FARGATE and FARGATE_SPOT - this module creates no capacity provider of its own."
  }
}
