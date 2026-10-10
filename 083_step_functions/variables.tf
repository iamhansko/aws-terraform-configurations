variable "aws_region" {
  type        = string
  default     = null
  description = "Target AWS region. When null, falls back to the provider default chain (AWS_REGION, profile, etc.)"

  validation {
    condition     = var.aws_region == null || can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a valid AWS region such as ap-northeast-2, or null to fall back to the provider default chain."
  }
}
variable "project_name" {
  type        = string
  default     = "validate-data"
  description = "Base name for the state machine, the three functions, the topic and their roles. The _monolithic template called this stack_name and used it the same way - it stood in for AWS::StackName because CloudFormation generated every name"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,40}$", var.project_name))
    error_message = "project_name must be 2-41 characters of lowercase letters, digits and hyphens."
  }
}
variable "lambda_runtime" {
  type        = string
  default     = "python3.13"
  description = "Runtime for all three functions. The _monolithic template used python3.9 for the two data functions and python3.13 for the third, and python3.9 has reached end of support - a function on a deprecated runtime keeps working until AWS stops it"

  validation {
    condition     = can(regex("^python3\\.(1[0-9]|[2-9][0-9])$", var.lambda_runtime))
    error_message = "lambda_runtime must be a supported python3.1x runtime, e.g. python3.13."
  }
}
variable "log_retention_days" {
  type        = number
  default     = 14
  description = "Retention for every log group here - three functions and the state machine. The _monolithic template declared none of them, so each was created on first use with retention set to never expire"

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be one of the retention periods CloudWatch Logs accepts."
  }
}
variable "state_machine_log_level" {
  type        = string
  default     = "ALL"
  description = "How much of each execution is logged. ALL, where the _monolithic template configured no logging while granting its role logs:* on everything. OFF removes both the log group and those permissions"

  validation {
    condition     = contains(["ALL", "ERROR", "FATAL", "OFF"], var.state_machine_log_level)
    error_message = "state_machine_log_level must be ALL, ERROR, FATAL or OFF."
  }
}
variable "notification_email_addresses" {
  type        = list(string)
  default     = []
  description = <<-DESC
    Addresses subscribed to the notification topic. Empty by default, as the _monolithic template had it -
    and worth knowing what that means: both notification states publish successfully to a topic with no
    subscribers, so the execution succeeds and nobody is told anything.

    An email subscription is created pending and delivers nothing until the address owner clicks the
    confirmation link, which Terraform cannot do on their behalf. That is why this is empty rather than
    defaulting to something that looks finished.
  DESC

  validation {
    condition     = alltrue([for address in var.notification_email_addresses : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", address))])
    error_message = "notification_email_addresses must contain email addresses."
  }
}
variable "demo_executions" {
  type = map(object({
    name = string
    age  = number
  }))
  default = {
    valid = {
      name = "Gildong"
      age  = 25
    }
    invalid = {
      name = "Hyunsu"
      age  = 0
    }
  }
  description = <<-DESC
    Executions started at apply time, keyed by a label. The two defaults are the _monolithic template's: one
    input that passes validation and one that does not, so both branches of the Choice state are exercised by
    a single apply.

    The second is the interesting one. age 0 fails the validate function's check, so the machine takes
    NotifyFailed and the execution still finishes as SUCCEEDED - a failed validation is not a failed
    execution, which is the distinction this demo is for.

    A map rather than a list because the keys become resource addresses (rules.md B-8). Set {} to create the
    state machine without running anything.
  DESC

  validation {
    condition     = alltrue([for label in keys(var.demo_executions) : can(regex("^[a-zA-Z0-9._-]+$", label))])
    error_message = "demo_executions keys are labels used in resource addresses, so each must be letters, digits, dots, underscores or hyphens."
  }
  validation {
    condition     = alltrue([for execution in values(var.demo_executions) : execution.age >= 0])
    error_message = "demo_executions ages must be zero or greater. Zero is the value that fails validation, which is the point of the second default."
  }
}
variable "starter_function_timeout" {
  type        = number
  default     = 60
  description = "How long the execution starter may run, sixty seconds as the _monolithic template had it. It makes one StartExecution call and returns - it does not wait for the execution to finish, so the state machine's own duration is not bounded by this"

  validation {
    condition     = var.starter_function_timeout >= 1 && var.starter_function_timeout <= 900
    error_message = "starter_function_timeout must be between 1 and 900 seconds."
  }
}
