variable "name" {
  type        = string
  description = "Name of the cluster. No default: CloudFormation generated this name and Terraform requires one, so the caller derives it from the project name"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]{0,254}$", var.name))
    error_message = "name must be 1-255 characters of letters, digits, underscores and hyphens, starting with a letter or digit."
  }
}
variable "container_insights" {
  type        = string
  default     = "enhanced"
  description = <<-DESC
    Value of the containerInsights cluster setting. "enhanced" is what the _monolithic template set and it
    is kept, because the ECS MCP server's troubleshooting tools read what the cluster reports, and enhanced
    is the mode that reports per-task and per-container metrics rather than cluster and service totals.

    It bills per observed resource. An idle cluster costs little; every service Q deploys into it adds to
    that - "disabled" turns it off without changing anything else here.
  DESC

  validation {
    condition     = contains(["enhanced", "enabled", "disabled"], var.container_insights)
    error_message = "container_insights must be enhanced, enabled or disabled. ECS rejects any other value at apply time with InvalidParameterException; plan does not check it."
  }
}
