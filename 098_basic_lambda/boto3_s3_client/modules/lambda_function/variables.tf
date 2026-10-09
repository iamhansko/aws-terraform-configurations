variable "function_name" {
  type        = string
  description = "Name of the function, which also fixes its log group path at /aws/lambda/<name>"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]{1,64}$", var.function_name))
    error_message = "function_name must be 1-64 characters of letters, digits, hyphens and underscores - Lambda's own limit."
  }
}
variable "source_directory" {
  type        = string
  description = "Directory holding the handler source, resolved by the caller. Taken as a path rather than looked up here so the module does not need to know where in the repository the Python lives (rules.md B-6)"

  validation {
    condition     = length(var.source_directory) > 0
    error_message = "source_directory must not be empty."
  }
}
variable "handler" {
  type        = string
  default     = "index.lambda_handler"
  description = "Entry point, in <module>.<function> form"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_./-]+\\.[a-zA-Z0-9_]+$", var.handler))
    error_message = "handler must be in <module>.<function> form, e.g. index.lambda_handler."
  }
}
variable "runtime" {
  type        = string
  default     = "python3.13"
  description = "Lambda runtime"

  validation {
    condition     = can(regex("^python3\\.(1[0-9]|[2-9][0-9])$", var.runtime))
    error_message = "runtime must be a supported python3.1x runtime, e.g. python3.13."
  }
}
variable "timeout" {
  type        = number
  default     = 300
  description = "How long the function may run before Lambda stops it"

  validation {
    condition     = var.timeout >= 1 && var.timeout <= 900
    error_message = "timeout must be between 1 and 900 seconds - Lambda's own range."
  }
}
variable "memory_size" {
  type        = number
  default     = 128
  description = "Memory, and with it the share of CPU. The handler reads the whole object into a string and builds a second one, so an object larger than roughly half of this fails with a memory error rather than a timeout"

  validation {
    condition     = var.memory_size >= 128 && var.memory_size <= 10240
    error_message = "memory_size must be between 128 and 10240 MB."
  }
}
variable "environment_variables" {
  type        = map(string)
  default     = {}
  description = "Environment variables for the function. Empty here: the handler takes the bucket and key out of the event it is given rather than from configuration. The block below is dynamic for that reason - an empty environment block is not the same as no block, and Lambda reports a configuration difference on every plan for one"

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
variable "iam_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"]
  description = "Managed policy ARNs attached to the function's role. The caller decides how broad these are; the module's own default is only the log-writing policy, which is the minimum for a function whose failures should be explicable"

  validation {
    condition     = length(var.iam_policy_arns) > 0 && alltrue([for arn in var.iam_policy_arns : can(regex("^arn:aws[a-z-]*:iam::", arn))])
    error_message = "iam_policy_arns must be a non-empty list of IAM policy ARNs."
  }
}
variable "additional_policy_statements" {
  type        = list(any)
  default     = []
  description = "Statements attached as an inline policy on top of iam_policy_arns. Empty creates no inline policy at all, rather than an empty one, which IAM rejects. Supplied by the caller because only the caller knows which resources the function touches (rules.md B-6)"

  validation {
    # The shape, not the contents - a statement is free-form by nature. A statement missing Effect or Action
    # is accepted by jsonencode and rejected by IAM with MalformedPolicyDocument, which names the policy
    # rather than the statement.
    condition     = alltrue([for statement in var.additional_policy_statements : can(statement.Effect) && can(statement.Action)])
    error_message = "additional_policy_statements entries must each have at least an Effect and an Action. IAM rejects a statement without them with MalformedPolicyDocument at apply time."
  }
}
variable "source_bucket_arn" {
  type        = string
  description = <<-DESC
    ARN of the bucket allowed to invoke this function, taken from the bucket module's output rather than
    assembled from a name (rules.md B-6).

    The _monolithic template built this string itself - "arn:aws:s3:::sensitive-$${random_string}" - because
    referencing the bucket resource would have closed a cycle with the bucket's notification configuration.
    That cycle is gone here: the notification lives in the root, so this can be a real reference and the
    permission cannot end up pointing at a bucket that does not exist.
  DESC

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:s3:::[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.source_bucket_arn))
    error_message = "source_bucket_arn must be an S3 bucket ARN (e.g. arn:aws:s3:::my-bucket) - a bucket ARN has no region or account segment, and must not include a key suffix."
  }
}
variable "log_tail_minutes" {
  type        = number
  default     = 30
  description = "How far back the log verification command this module exposes reads"

  validation {
    condition     = var.log_tail_minutes >= 1
    error_message = "log_tail_minutes must be at least 1."
  }
}
