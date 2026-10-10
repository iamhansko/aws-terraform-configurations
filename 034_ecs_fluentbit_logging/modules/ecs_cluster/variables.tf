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
  default     = "disabled"
  description = <<-DESC
    Value of the containerInsights cluster setting.
    The _monolithic template declared no setting at all, which means the cluster silently followed the
    account's ECS default - so the same template could produce a billed cluster in one account and not in
    another. This states it instead, and states it off.
    Off is the right default for this project specifically: Container Insights works by writing metrics
    and, in "enhanced" mode, per-container performance logs into CloudWatch. In a project whose purpose is
    to watch what arrives in a log group, that is a second, much larger log producer sharing the bill with
    the one being demonstrated. Set it to "enabled" or "enhanced" deliberately.
  DESC
  validation {
    condition     = contains(["enhanced", "enabled", "disabled"], var.container_insights)
    error_message = "container_insights must be enhanced, enabled or disabled. ECS rejects any other value at apply time with InvalidParameterException; plan does not check it."
  }
}
