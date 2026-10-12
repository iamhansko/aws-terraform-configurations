variable "name" {
  type        = string
  description = "Name of the ECS cluster"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,255}$", var.name))
    error_message = "name must be 1-255 letters, digits, hyphens and underscores."
  }
}
variable "container_insights" {
  type        = string
  default     = "enabled"
  description = "Container Insights setting, enabled as the blueprint had it. enhanced adds per-container metrics at a higher price; disabled turns the cluster's metrics off"

  validation {
    condition     = contains(["enabled", "enhanced", "disabled"], var.container_insights)
    error_message = "container_insights must be enabled, enhanced or disabled."
  }
}
