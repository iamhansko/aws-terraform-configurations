variable "name" {
  type        = string
  default     = "ecs-cicd-cluster"
  description = "Name of the ECS cluster, as the _monolithic template named it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,255}$", var.name))
    error_message = "name must be 1-255 characters of letters, digits, underscores or hyphens, which is what ECS accepts for a cluster name."
  }
}
variable "container_insights" {
  type        = string
  default     = "enhanced"
  description = "Container Insights level. \"enhanced\" as the _monolithic template had it, which is what produces the per-task and per-service metrics the blue/green cutover is watched with - and which bills per observed task rather than being free like \"enabled\""

  validation {
    condition     = contains(["enhanced", "enabled", "disabled"], var.container_insights)
    error_message = "container_insights must be enhanced, enabled or disabled."
  }
}
