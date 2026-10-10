variable "name" {
  type        = string
  description = "Name of the cluster. The container instance launch template writes this into /etc/ecs/ecs.config and the service, the capacity provider association and the CodeDeploy deployment group all name it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,255}$", var.name))
    error_message = "name must be 1-255 characters of letters, digits, underscores and hyphens, which is what ECS accepts for a cluster name."
  }
}
variable "container_insights" {
  type        = string
  default     = "disabled"
  description = "Container Insights setting, as the _monolithic template had it. Disabled, which keeps the project from creating a CloudWatch Logs group and metric stream nothing here reads"

  validation {
    condition     = contains(["enabled", "disabled", "enhanced"], var.container_insights)
    error_message = "container_insights must be enabled, disabled or enhanced."
  }
}
variable "execute_command_logging" {
  type        = string
  default     = "DEFAULT"
  description = "Where ECS Exec session output goes, as the _monolithic template had it. DEFAULT means the awslogs configuration of the container being entered, with no separate audit destination"

  validation {
    condition     = contains(["NONE", "DEFAULT", "OVERRIDE"], var.execute_command_logging)
    error_message = "execute_command_logging must be NONE, DEFAULT or OVERRIDE. OVERRIDE additionally requires a log group or S3 bucket, which this module does not take."
  }
}
