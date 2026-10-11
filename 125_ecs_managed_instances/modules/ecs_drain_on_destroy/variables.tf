variable "function_name" {
  type        = string
  description = "Name of the drain function"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,64}$", var.function_name))
    error_message = "function_name must be 1-64 characters of letters, digits, hyphens and underscores."
  }
}
variable "runtime" {
  type        = string
  default     = "python3.14"
  description = "Lambda runtime, as the _monolithic template had it"

  validation {
    condition     = startswith(var.runtime, "python3.")
    error_message = "runtime must be a Python 3 Lambda runtime - the handler is Python."
  }
}
variable "timeout_seconds" {
  type        = number
  default     = 900
  description = "How long the drain may wait for the instances to go, as the _monolithic template had it. 900 is Lambda's maximum; when it runs out the destroy fails at this resource rather than continuing with instances still running"

  validation {
    condition     = var.timeout_seconds >= 60 && var.timeout_seconds <= 900
    error_message = "timeout_seconds must be between 60 and 900."
  }
}
variable "cluster_name" {
  type        = string
  description = "Cluster to drain"

  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "cluster_name must not be empty."
  }
}
variable "cluster_arn" {
  type        = string
  description = "ARN of that cluster, for scoping the function's ecs:DescribeClusters"

  validation {
    condition     = can(regex("^arn:aws[a-zA-Z-]*:ecs:[a-z0-9-]+:[0-9]{12}:cluster/", var.cluster_arn))
    error_message = "cluster_arn must be an ECS cluster ARN."
  }
}
variable "service_names" {
  type        = list(string)
  description = "Services scaled to zero before waiting. Taken from the service modules' outputs, which is also what orders this before them on destroy"

  validation {
    condition     = length(var.service_names) > 0
    error_message = "service_names must contain at least one service."
  }
}
variable "service_arns" {
  type        = list(string)
  description = "ARNs of the same services, for scoping the function's ecs:UpdateService"

  validation {
    condition     = length(var.service_arns) > 0 && alltrue([for arn in var.service_arns : can(regex("^arn:aws[a-zA-Z-]*:ecs:[a-z0-9-]+:[0-9]{12}:service/", arn))])
    error_message = "service_arns must contain ECS service ARNs."
  }
}
variable "log_retention_in_days" {
  type        = number
  default     = 7
  description = "Days the function's log group keeps events"

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365], var.log_retention_in_days)
    error_message = "log_retention_in_days must be one of 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180 or 365."
  }
}
