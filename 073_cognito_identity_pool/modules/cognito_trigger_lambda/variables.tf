variable "function_name" {
  type        = string
  description = "Name of the function"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]{1,64}$", var.function_name))
    error_message = "function_name must be 1-64 characters of letters, digits, hyphens and underscores."
  }
}
variable "source_file" {
  type        = string
  description = "The handler's source file. Zipped on its own, so it must not import anything but the runtime's built-ins"

  validation {
    condition     = endswith(var.source_file, ".mjs") || endswith(var.source_file, ".js")
    error_message = "source_file must be a .mjs or .js file."
  }
}
variable "handler" {
  type        = string
  default     = "app.lambdaHandler"
  description = "Handler, as <file name without extension>.<export>. app.lambdaHandler, as the workshop's SAM template had it"

  validation {
    condition     = can(regex("^[A-Za-z0-9_-]+\\.[A-Za-z0-9_]+$", var.handler))
    error_message = "handler must be <file>.<export>, e.g. app.lambdaHandler."
  }
}
variable "runtime" {
  type        = string
  default     = "nodejs22.x"
  description = "Lambda runtime, as the workshop's SAM template had it. nodejs22.x is the newest runtime that still provides context.done, which the workshop's handler returns through"

  validation {
    condition     = can(regex("^nodejs[0-9]+\\.x$", var.runtime))
    error_message = "runtime must be a Node.js runtime (e.g. nodejs22.x)."
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
