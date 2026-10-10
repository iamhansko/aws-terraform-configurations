variable "function_name" {
  type        = string
  description = "Name of the function. Unique per account and region"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,64}$", var.function_name))
    error_message = "function_name must be 1-64 characters of letters, digits, hyphens and underscores."
  }
}
variable "handler" {
  type        = string
  description = "Handler as <module>.<function>. Load-bearing: it names a file and a function inside Lambda/code.zip, which comes from the sample repository and not from this configuration"

  validation {
    condition     = can(regex("^[A-Za-z_][A-Za-z0-9_]*\\.[A-Za-z_][A-Za-z0-9_]*$", var.handler))
    error_message = "handler must be <module>.<function>, e.g. MatchRequest.lambda_handler."
  }
}
variable "runtime" {
  type        = string
  default     = "python3.13"
  description = "Lambda runtime, as the _monolithic template had it"

  validation {
    condition     = can(regex("^python3\\.[0-9]+$", var.runtime))
    error_message = "runtime must be a Python 3 runtime identifier such as python3.13. The package is Python source plus a vendored redis client."
  }
}
variable "timeout" {
  type        = number
  default     = 60
  description = "Function timeout in seconds, as the _monolithic template had it"

  validation {
    condition     = var.timeout >= 1 && var.timeout <= 900
    error_message = "timeout must be between 1 and 900 seconds."
  }
}
variable "memory_size" {
  type        = number
  default     = 128
  description = "Function memory in MB. The _monolithic template left it at the Lambda default, which is this"

  validation {
    condition     = var.memory_size >= 128 && var.memory_size <= 10240
    error_message = "memory_size must be between 128 and 10240 MB."
  }
}
variable "s3_bucket" {
  type        = string
  description = "Bucket holding the deployment package. The package is uploaded there by the Windows instance, not by Terraform, and CreateFunction fails immediately on a missing object - which is why the root passes this and s3_key through a waiter that has seen the object"

  validation {
    condition     = length(var.s3_bucket) >= 3 && length(var.s3_bucket) <= 63
    error_message = "s3_bucket must be a bucket name of 3-63 characters."
  }
}
variable "s3_key" {
  type        = string
  description = "Key of the deployment package in s3_bucket"

  validation {
    condition     = length(var.s3_key) > 0 && !startswith(var.s3_key, "/")
    error_message = "s3_key must be a non-empty object key without a leading slash."
  }
}
variable "role_name_prefix" {
  type        = string
  description = "Prefix for the generated execution role name. The _monolithic template left its roles unnamed"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,38}$", var.role_name_prefix))
    error_message = "role_name_prefix must be 1-38 characters of letters, digits and +=,.@_-."
  }
}
variable "managed_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"]
  description = "AWS managed policies the function needs to run at all - logging, and for a VPC-attached function the ENI permissions in AWSLambdaVPCAccessExecutionRole"

  validation {
    condition     = alltrue([for arn in var.managed_policy_arns : can(regex("^arn:aws[a-z-]*:iam::", arn))])
    error_message = "managed_policy_arns must contain valid IAM policy ARNs."
  }
}
variable "additional_policy_arns" {
  type        = list(string)
  default     = []
  description = "Further managed policies on top of the scoped grants. Empty by default; this is where the _monolithic template's AmazonDynamoDBFullAccess, AmazonSQSFullAccess or AmazonVPCFullAccess would go back if a scoped grant turns out to be missing something"

  validation {
    condition     = alltrue([for arn in var.additional_policy_arns : can(regex("^arn:aws[a-z-]*:iam::", arn))])
    error_message = "additional_policy_arns must contain valid IAM policy ARNs."
  }
}
variable "inline_policies" {
  type        = map(string)
  default     = {}
  description = "Inline policy documents (JSON) attached to the execution role, keyed by policy name. A map with caller-chosen literal keys because the documents name resources from other modules (rules.md B-8)"

  validation {
    condition     = alltrue([for name in keys(var.inline_policies) : can(regex("^[a-zA-Z0-9+=,.@_-]{1,128}$", name))])
    error_message = "inline_policies keys are IAM policy names: 1-128 characters of letters, digits and +=,.@_-."
  }
}
variable "environment_variables" {
  type        = map(string)
  default     = {}
  description = "Environment variables for the function. Empty omits the environment block"

  validation {
    condition     = alltrue([for name in keys(var.environment_variables) : can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", name))])
    error_message = "environment_variables keys must start with a letter and contain only letters, digits and underscores, which is what Lambda accepts as a variable name."
  }
}
variable "subnet_ids" {
  type        = list(string)
  default     = []
  description = "Subnets to attach the function to. Empty leaves it outside the VPC, which is right for every function here that does not talk to Redis"

  validation {
    condition     = alltrue([for id in var.subnet_ids : can(regex("^subnet-[0-9a-f]+$", id))])
    error_message = "subnet_ids must contain valid subnet IDs (e.g. subnet-0123456789abcdef0)."
  }
}
variable "security_group_ids" {
  type        = list(string)
  default     = []
  description = "Security groups for the function's ENIs, used only when subnet_ids is set. A list because it is assigned to an attribute, not iterated (rules.md B-8)"

  validation {
    condition     = alltrue([for id in var.security_group_ids : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "security_group_ids must contain valid security group IDs (e.g. sg-0123456789abcdef0)."
  }
}
variable "event_source_mappings" {
  type = map(object({
    event_source_arn  = string
    starting_position = optional(string)
  }))
  default     = {}
  description = "Polling event sources (an SQS queue, a DynamoDB stream), keyed by a caller-chosen label. starting_position is required for a stream and must be null for a queue"

  validation {
    condition     = alltrue([for m in values(var.event_source_mappings) : m.starting_position == null || contains(["TRIM_HORIZON", "LATEST"], m.starting_position)])
    error_message = "event_source_mappings starting_position must be TRIM_HORIZON, LATEST or null."
  }
}
