variable "name" {
  type        = string
  description = "Name of the ECS cluster"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,255}$", var.name))
    error_message = "name must be 1-255 characters of letters, digits, underscores and hyphens."
  }
}
variable "container_insights" {
  type        = string
  default     = "disabled"
  description = "Container Insights setting on the cluster: disabled, enabled or enhanced"

  validation {
    condition     = contains(["enabled", "disabled", "enhanced"], var.container_insights)
    error_message = "container_insights must be enabled, disabled or enhanced."
  }
}
