variable "function_name" {
  type        = string
  description = "Function name. Unique per account and region"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+$", var.function_name)) && length(var.function_name) <= 64
    error_message = "function_name must be 1-64 characters of letters, digits, hyphens and underscores."
  }
}
variable "handler" {
  type        = string
  description = "<module>.<function> inside the package, e.g. GetRank.handler"

  validation {
    condition     = can(regex("^[A-Za-z_][A-Za-z0-9_]*\\.[A-Za-z_][A-Za-z0-9_]*$", var.handler))
    error_message = "handler must be <module>.<function>, e.g. MatchRequest.lambda_handler."
  }
}
variable "runtime" {
  type        = string
  default     = "python3.13"
  description = "Lambda runtime. The package is the game sample's Lambda/code.zip, which is Python with a pure-Python redis client vendored in"

  validation {
    condition     = can(regex("^python3\\.[0-9]+$", var.runtime))
    error_message = "runtime must be a Python 3 runtime such as python3.13, because the package is Python."
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
  description = "Memory in MB. 128 is Lambda's default, which is what the _monolithic template got by not setting one"

  validation {
    condition     = var.memory_size >= 128 && var.memory_size <= 10240
    error_message = "memory_size must be between 128 and 10240 MB."
  }
}
variable "s3_bucket" {
  type        = string
  description = "Bucket holding the deployment package. CreateFunction fails at once if the object is missing, which is why the root passes this and s3_key through a waiter that has seen the object"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]+$", var.s3_bucket)) && length(var.s3_bucket) <= 63
    error_message = "s3_bucket must be a valid S3 bucket name."
  }
}
variable "s3_key" {
  type        = string
  description = "Object key of the deployment package"

  validation {
    condition     = length(var.s3_key) > 0 && !startswith(var.s3_key, "/")
    error_message = "s3_key must be a non-empty object key without a leading slash."
  }
}
variable "partition" {
  type        = string
  description = "AWS partition, for the AWS managed execution policy ARN"

  validation {
    condition     = contains(["aws", "aws-cn", "aws-us-gov"], var.partition)
    error_message = "partition must be aws, aws-cn or aws-us-gov."
  }
}
variable "role_name_prefix" {
  type        = string
  description = "Prefix for the execution role's name. The provider appends a unique suffix"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]+$", var.role_name_prefix)) && length(var.role_name_prefix) <= 38
    error_message = "role_name_prefix must be 1-38 characters from the set IAM accepts for a role name (name_prefix is capped at 38)."
  }
}
variable "policy_statements" {
  type = list(object({
    sid       = string
    actions   = list(string)
    resources = list(string)
  }))
  default     = []
  description = "Allow statements for the execution role's inline policy - the calls this function's handler actually makes, on the resources it makes them on (rules.md A-5). Empty means no inline policy"

  validation {
    condition     = alltrue([for statement in var.policy_statements : can(regex("^[A-Za-z0-9]+$", statement.sid)) && length(statement.actions) > 0 && length(statement.resources) > 0])
    error_message = "Each policy statement needs an alphanumeric sid and at least one action and one resource."
  }
}
variable "additional_policy_arns" {
  type        = list(string)
  default     = []
  description = "Managed policy ARNs attached on top of the execution policy and the scoped inline policy. Empty by default; the _monolithic template's full-access policies are one entry away here if the scoped grants turn out to miss something"

  validation {
    condition     = alltrue([for arn in var.additional_policy_arns : can(regex("^arn:aws[a-z-]*:iam::", arn))])
    error_message = "additional_policy_arns must contain valid IAM policy ARNs."
  }
}
variable "environment_variables" {
  type        = map(string)
  default     = {}
  description = "Environment variables for the function. Empty means no environment block"

  validation {
    condition     = alltrue([for key in keys(var.environment_variables) : can(regex("^[a-zA-Z][a-zA-Z0-9_]+$", key))])
    error_message = "environment_variables keys must start with a letter and contain only letters, digits and underscores (at least two characters), which is what Lambda accepts."
  }
}
variable "vpc_subnet_ids" {
  type        = list(string)
  default     = []
  description = "Subnets the function's ENIs are placed in. Empty means the function is not VPC-attached. Non-empty also switches the execution policy from AWSLambdaBasicExecutionRole to AWSLambdaVPCAccessExecutionRole, which carries the same log permissions plus the ENI calls"

  validation {
    condition     = alltrue([for id in var.vpc_subnet_ids : can(regex("^subnet-[0-9a-f]+$", id))])
    error_message = "vpc_subnet_ids must contain valid subnet IDs."
  }
}
variable "vpc_security_group_ids" {
  type        = list(string)
  default     = []
  description = "Security groups on the function's ENIs. Required exactly when vpc_subnet_ids is set"

  validation {
    condition     = alltrue([for id in var.vpc_security_group_ids : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "vpc_security_group_ids must contain valid security group IDs."
  }
  validation {
    # The pair is what is constrained, not either list on its own (rules.md B-1). Lambda rejects a vpc_config
    # with subnets and no security groups, and security groups with no subnets would silently do nothing.
    condition     = (length(var.vpc_subnet_ids) > 0) == (length(var.vpc_security_group_ids) > 0)
    error_message = "vpc_security_group_ids must be set exactly when vpc_subnet_ids is set."
  }
}
variable "event_source_mappings" {
  type = map(object({
    event_source_arn  = string
    starting_position = optional(string)
  }))
  default     = {}
  description = "Poll-based triggers keyed by a caller-chosen label. A map with literal keys because the ARNs are other modules' outputs, unknown at plan (rules.md B-8). starting_position is required for a stream and must be null for SQS"

  validation {
    condition     = alltrue([for label in keys(var.event_source_mappings) : can(regex("^[a-zA-Z0-9_-]+$", label))])
    error_message = "event_source_mappings keys must be labels of letters, digits, hyphens and underscores."
  }
  validation {
    condition     = alltrue([for mapping in values(var.event_source_mappings) : mapping.starting_position == null || contains(["TRIM_HORIZON", "LATEST"], coalesce(mapping.starting_position, "LATEST"))])
    error_message = "starting_position must be TRIM_HORIZON, LATEST or null."
  }
}
