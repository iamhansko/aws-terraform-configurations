variable "function_name" {
  type        = string
  description = "Name of the function, and of its log group /aws/lambda/<function_name>"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]{1,64}$", var.function_name))
    error_message = "function_name must be 1-64 characters of letters, digits, hyphens and underscores."
  }
}
variable "description" {
  type        = string
  default     = ""
  description = "Description of the function shown in the console"

  validation {
    condition     = length(var.description) <= 256
    error_message = "description must be 256 characters or fewer."
  }
}
variable "source_dir" {
  type        = string
  description = "Directory zipped as the function's package. Only the standard library and what the runtime or a layer provides can be imported, because nothing is installed into it"

  validation {
    # The handler's module has to be a file at the top of the directory, or the function fails at its first
    # invocation with Runtime.ImportModuleError rather than here (rules.md B-1).
    condition     = fileexists("${var.source_dir}/${split(".", var.handler)[0]}.py")
    error_message = "source_dir must contain <module>.py for the module named in handler (index.py for index.lambda_handler)."
  }
}
variable "handler" {
  type        = string
  default     = "app.lambda_handler"
  description = "Handler, as <module>.<function>. app.lambda_handler, as most of the SAM templates had it"

  validation {
    condition     = can(regex("^[A-Za-z0-9_]+\\.[A-Za-z0-9_]+$", var.handler))
    error_message = "handler must be <module>.<function>, e.g. index.lambda_handler."
  }
}
variable "runtime" {
  type        = string
  description = "Python runtime, e.g. python3.13. Passed in by the caller so it is the same value the layer was built for"

  validation {
    condition     = can(regex("^python3\\.[0-9]+$", var.runtime))
    error_message = "runtime must be a Python runtime, e.g. python3.13."
  }
}
variable "architecture" {
  type        = string
  default     = "x86_64"
  description = "Instruction set architecture of the function"

  validation {
    condition     = contains(["x86_64", "arm64"], var.architecture)
    error_message = "architecture must be x86_64 or arm64."
  }
}
variable "memory_size" {
  type        = number
  default     = 1024
  description = "Memory in MB. 1024, as the SAM templates' Globals set it for every function"

  validation {
    condition     = var.memory_size >= 128 && var.memory_size <= 10240 && floor(var.memory_size) == var.memory_size
    error_message = "memory_size must be an integer between 128 and 10240."
  }
}
variable "timeout" {
  type        = number
  description = "Seconds an invocation may take"

  validation {
    condition     = var.timeout >= 1 && var.timeout <= 900 && floor(var.timeout) == var.timeout
    error_message = "timeout must be an integer between 1 and 900."
  }
}
variable "environment" {
  type        = map(string)
  default     = {}
  description = "Environment variables. Readable in clear by anyone with lambda:GetFunctionConfiguration, so a secret placed here is only as private as that permission"

  validation {
    condition     = alltrue([for key in keys(var.environment) : can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", key))])
    error_message = "environment keys must start with a letter and contain only letters, digits and underscores."
  }
}
variable "layers" {
  type        = list(string)
  default     = []
  description = "Layer version ARNs, in the order Lambda extracts them into /opt"

  validation {
    condition     = length(var.layers) <= 5
    error_message = "layers must contain at most five layer versions, the Lambda limit."
  }
}
variable "inline_policies" {
  type        = map(string)
  default     = {}
  description = "IAM policy documents attached to the function's role, keyed by a caller-chosen label. A map rather than a list because a document usually names a resource another module creates, unknown until apply, and for_each needs keys known at plan (rules.md B-8)"

  validation {
    condition     = alltrue([for label in keys(var.inline_policies) : can(regex("^[a-zA-Z0-9_-]{1,64}$", label))])
    error_message = "inline_policies keys are used in the policy names, so each must be 1-64 letters, digits, underscores or hyphens."
  }
}
variable "log_retention_in_days" {
  type        = number
  default     = 7
  description = "Days the function's log group keeps events"

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_in_days)
    error_message = "log_retention_in_days must be one of the values CloudWatch Logs accepts: 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288 or 3653."
  }
}
