variable "name" {
  type        = string
  description = "Name of the function, and the basis for its role and log group names. CloudFormation generated these names; Terraform requires one, so the caller derives it from the project name"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]{1,64}$", var.name))
    error_message = "name must be 1-64 characters of letters, digits, hyphens and underscores - Lambda's own limit."
  }
}
variable "source_dir" {
  type        = string
  description = "Directory holding the function's source. Zipped by the archive provider at plan time, so a change to the code is a change in plan rather than something discovered on the next apply"

  validation {
    condition     = length(var.source_dir) > 0
    error_message = "source_dir must not be empty."
  }
}
variable "handler" {
  type        = string
  default     = "index.lambda_handler"
  description = "Entry point, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_./-]+\\.[a-zA-Z0-9_]+$", var.handler))
    error_message = "handler must be in <module>.<function> form, e.g. index.lambda_handler."
  }
}
variable "runtime" {
  type        = string
  default     = "python3.13"
  description = "Lambda runtime. The _monolithic template used python3.9 for two of its three functions and python3.13 for the third - python3.9 reached end of support, and a function on a deprecated runtime keeps working until AWS stops it, which is the worst way to find out"

  validation {
    condition     = can(regex("^python3\\.(1[0-9]|[2-9][0-9])$", var.runtime))
    error_message = "runtime must be a supported python3.1x runtime, e.g. python3.13. Runtimes before 3.10 have reached end of support."
  }
}
variable "timeout" {
  type        = number
  default     = 10
  description = "How long the function may run. Ten seconds: these functions transform a small object or make one API call, and Lambda's own default of three is tight enough that a cold start plus one SDK call can reach it"

  validation {
    condition     = var.timeout >= 1 && var.timeout <= 900
    error_message = "timeout must be between 1 and 900 seconds - Lambda's own range."
  }
}
variable "memory_size" {
  type        = number
  default     = 128
  description = "Memory, and therefore the share of CPU. 128MB, Lambda's minimum, which is what these functions need"

  validation {
    condition     = var.memory_size >= 128 && var.memory_size <= 10240
    error_message = "memory_size must be between 128 and 10240 MB."
  }
}
variable "environment_variables" {
  type        = map(string)
  default     = {}
  description = "Environment variables for the function. Empty for all three functions here, which is why the environment block is dynamic - an empty block is not the same as no block, and Lambda shows a configuration difference for one"

  validation {
    condition     = alltrue([for key in keys(var.environment_variables) : can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", key))])
    error_message = "environment_variables keys must start with a letter and contain only letters, digits and underscores - Lambda's own rule for an environment variable name."
  }
  validation {
    # Lambda reserves these and rejects the whole function configuration if one is set, which is an
    # apply-time InvalidParameterValueException naming the key.
    condition = length(setintersection(keys(var.environment_variables), [
      "AWS_REGION", "AWS_DEFAULT_REGION", "AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN",
      "AWS_LAMBDA_FUNCTION_NAME", "AWS_LAMBDA_FUNCTION_VERSION", "AWS_LAMBDA_FUNCTION_MEMORY_SIZE",
      "AWS_LAMBDA_LOG_GROUP_NAME", "AWS_LAMBDA_LOG_STREAM_NAME", "AWS_EXECUTION_ENV", "LAMBDA_TASK_ROOT",
      "LAMBDA_RUNTIME_DIR", "_HANDLER", "TZ",
    ])) == 0
    error_message = "environment_variables must not set a key Lambda reserves (AWS_REGION, AWS_ACCESS_KEY_ID, _HANDLER, TZ and the rest of the runtime's own variables). Lambda rejects the function configuration outright, and the error arrives at apply time."
  }
}
variable "log_retention_days" {
  type        = number
  default     = 14
  description = "How long the function's logs are kept. The _monolithic template declared no log group at all, so Lambda created one on first invocation with retention set to never expire - logs kept forever for a demo, billed forever"

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be one of the retention periods CloudWatch Logs accepts."
  }
}
variable "additional_policy_statements" {
  type = list(object({
    actions   = list(string)
    resources = list(string)
  }))
  default     = []
  description = "Allow statements added to the function's role beyond writing its own logs. Supplied by the caller because only the caller knows what the function calls - the starter function needs states:StartExecution on one state machine, the two data functions need nothing (rules.md B-6). Typed rather than list(any), so a misspelt key is a plan error instead of a statement IAM rejects at apply"

  validation {
    condition     = alltrue([for statement in var.additional_policy_statements : length(statement.actions) > 0 && alltrue([for action in statement.actions : can(regex("^[a-z0-9-]+:[A-Za-z0-9*]+$", action))])])
    error_message = "Each additional policy statement needs at least one action, each in service:Action form such as states:StartExecution."
  }
  validation {
    # Counted rather than pattern-checked: the resources are usually another module's ARNs, unknown until
    # apply, and an empty list is the mistake worth catching at plan.
    condition     = alltrue([for statement in var.additional_policy_statements : length(statement.resources) > 0])
    error_message = "Each additional policy statement needs at least one resource. Name the ARNs the function calls rather than leaving the statement open."
  }
}
