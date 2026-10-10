variable "name" {
  type        = string
  description = "Name of the state machine. CloudFormation generated it; Terraform requires one"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]{1,80}$", var.name))
    error_message = "name must be 1-80 characters of letters, digits, hyphens and underscores - Step Functions' own limit."
  }
}
variable "validate_function_arn" {
  type        = string
  description = "Function the first task state invokes. Passed in so the definition and the IAM policy name the same ARN - the _monolithic template's policy granted lambda:InvokeFunction on \"*\" instead (rules.md B-5/A-5)"

  validation {
    condition     = can(regex("^arn:aws:lambda:", var.validate_function_arn))
    error_message = "validate_function_arn must be a Lambda function ARN."
  }
}
variable "process_function_arn" {
  type        = string
  description = "Function the second task state invokes, on the valid branch"

  validation {
    condition     = can(regex("^arn:aws:lambda:", var.process_function_arn))
    error_message = "process_function_arn must be a Lambda function ARN."
  }
}
variable "notification_topic_arn" {
  type        = string
  description = "Topic both notification states publish to. The policy's sns:Publish is scoped to this one rather than to every topic in the account"

  validation {
    condition     = can(regex("^arn:aws:sns:", var.notification_topic_arn))
    error_message = "notification_topic_arn must be an SNS topic ARN."
  }
}
variable "log_level" {
  type        = string
  default     = "ALL"
  description = <<-DESC
    How much of each execution is logged. ALL, where the _monolithic template configured no logging at all -
    its role carried logs:* on every resource in the account and used none of it.

    That mattered more than it sounds: without execution logging, a failed execution can still be read from
    the execution history for 90 days and then is gone, and a Choice state that took the wrong branch leaves
    no record of the value it tested.
  DESC

  validation {
    condition     = contains(["ALL", "ERROR", "FATAL", "OFF"], var.log_level)
    error_message = "log_level must be ALL, ERROR, FATAL or OFF."
  }
}
variable "include_execution_data" {
  type        = bool
  default     = true
  description = "Whether the logs carry each state's input and output. True, which is what makes the log useful for a demo - and what would make it a liability for a state machine handling anything private, since the payloads land in CloudWatch Logs verbatim"
}
variable "log_retention_days" {
  type        = number
  default     = 14
  description = "How long execution logs are kept"

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be one of the retention periods CloudWatch Logs accepts."
  }
}
variable "tracing_enabled" {
  type        = bool
  default     = false
  description = "Whether X-Ray tracing is on. False, as the _monolithic template had it: it needs its own IAM permissions and X-Ray is billed per trace, and the execution history already shows the path a run took"
}
variable "comment" {
  type        = string
  default     = "name(String), age(PositiveInteger)"
  description = "Comment in the state machine definition, as the _monolithic template wrote it - it documents the shape of the input the first task expects"

  validation {
    condition     = length(trimspace(var.comment)) > 0
    error_message = "comment must not be empty. It is the only place the definition says what input the first task expects."
  }
}
