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
    is kept: it is the mode that reports per-task and per-container metrics rather than cluster and service
    totals.

    It bills per observed resource, which for a cluster of two container instances and a handful of tasks
    is small but is not nothing - "disabled" turns it off without changing anything else here.
  DESC

  validation {
    condition     = contains(["enhanced", "enabled", "disabled"], var.container_insights)
    error_message = "container_insights must be enhanced, enabled or disabled. ECS rejects any other value at apply time with InvalidParameterException; plan does not check it."
  }
}
variable "service_connect_defaults" {
  type = object({
    namespace = string
  })
  default     = null
  description = <<-DESC
    Default Service Connect namespace for the cluster, as an ARN of a Cloud Map namespace. Null declares no
    default, which is what a cluster whose services do not use Service Connect should have.

    A service that enables Service Connect without naming a namespace joins this one. If there is no
    default and the service names none either, CreateService fails at apply - plan cannot see it.
  DESC

  validation {
    condition     = var.service_connect_defaults == null || can(regex("^arn:aws[a-z-]*:servicediscovery:", var.service_connect_defaults.namespace))
    error_message = "service_connect_defaults.namespace must be the ARN of a Cloud Map namespace (arn:aws:servicediscovery:...), or service_connect_defaults must be null."
  }
}
