variable "function_name" {
  type        = string
  description = "Name of the function. Account-and-region unique"
  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,64}$", var.function_name))
    error_message = "function_name must be 1-64 characters of letters, digits, hyphens and underscores."
  }
}
variable "image_uri" {
  type        = string
  description = "Tagged image reference the function is created from. Lambda resolves the tag to a digest at create time and runs that digest from then on, so pushing over the tag later changes nothing until the function's code is updated"
  validation {
    condition     = can(regex("^[0-9]{12}\\.dkr\\.ecr\\.[a-z0-9-]+\\.amazonaws\\.com(\\.cn)?/[a-z0-9._/-]+(:[A-Za-z0-9_][A-Za-z0-9._-]{0,127}|@sha256:[0-9a-f]{64})$", var.image_uri))
    error_message = "image_uri must be a private ECR image reference with a tag or a digest - Lambda does not run images from other registries."
  }
}
variable "ecr_repository_name" {
  type        = string
  description = "Repository the image lives in, which this module grants the Lambda service pull access to"
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9._/-]{1,255}$", var.ecr_repository_name))
    error_message = "ecr_repository_name must start with a lowercase letter or digit and contain only lowercase letters, digits and . _ / -."
  }
}
variable "timeout" {
  type        = number
  default     = 15
  description = "Seconds an invocation may run"
  validation {
    condition     = var.timeout >= 1 && var.timeout <= 900
    error_message = "timeout must be between 1 and 900 seconds."
  }
}
variable "memory_size" {
  type        = number
  default     = 128
  description = "Memory in MB, which also sets the function's CPU share"
  validation {
    condition     = var.memory_size >= 128 && var.memory_size <= 10240
    error_message = "memory_size must be between 128 and 10240 MB."
  }
}
variable "environment_variables" {
  type        = map(string)
  default     = {}
  description = "Environment the handler reads its bucket, key and source URL from"
  validation {
    condition     = alltrue([for key in keys(var.environment_variables) : can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", key)) && !startswith(key, "AWS_")])
    error_message = "environment_variables keys must start with a letter, contain only letters, digits and underscores, and not start with AWS_, which Lambda reserves."
  }
}
variable "result_bucket_arn" {
  type        = string
  description = "Bucket the handler writes into. The role's one S3 grant is scoped to this bucket and result_object_key"
  validation {
    condition     = can(regex("^arn:aws[a-z-]*:s3:::[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.result_bucket_arn))
    error_message = "result_bucket_arn must be an S3 bucket ARN."
  }
}
variable "result_object_key" {
  type        = string
  description = "The one key the handler writes. The same value reaches the handler as OBJECT_KEY, so the grant and the write cannot name different objects (rules.md B-5)"
  validation {
    condition     = length(var.result_object_key) >= 1 && length(var.result_object_key) <= 1024 && !startswith(var.result_object_key, "/")
    error_message = "result_object_key must be 1-1024 characters and must not start with a slash."
  }
}
variable "role_name_prefix" {
  type        = string
  description = "Prefix for the generated execution role name"
  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,38}$", var.role_name_prefix))
    error_message = "role_name_prefix must be 1-38 characters from the IAM name character set, leaving room for the suffix the provider appends within IAM's 64-character limit."
  }
}
variable "managed_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"]
  description = "Managed policies the function needs to run at all. AWSLambdaBasicExecutionRole is what lets it write its own logs"
  validation {
    condition     = alltrue([for arn in var.managed_policy_arns : can(regex("^arn:aws[a-z-]*:iam::", arn))])
    error_message = "managed_policy_arns must contain valid IAM policy ARNs."
  }
}
variable "additional_policy_arns" {
  type        = list(string)
  default     = []
  description = "Further managed policies on the execution role. Empty: the handler's one S3 call is granted inline. Set [\"arn:aws:iam::aws:policy/AmazonS3FullAccess\"] to get the _monolithic template's breadth back"
  validation {
    condition     = alltrue([for arn in var.additional_policy_arns : can(regex("^arn:aws[a-z-]*:iam::", arn))])
    error_message = "additional_policy_arns must contain valid IAM policy ARNs."
  }
}
variable "log_retention_in_days" {
  type        = number
  default     = 14
  description = "Days CloudWatch keeps the function's log events"
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_in_days)
    error_message = "log_retention_in_days must be a value CloudWatch Logs accepts (1, 3, 5, 7, 14, 30, ...)."
  }
}
variable "region" {
  type        = string
  description = "Region the function is created in, for the ARNs this module assembles before the function exists. Passed in so the module declares no data source"
  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.region))
    error_message = "region must be a region code such as ap-northeast-2."
  }
}
variable "account_id" {
  type        = string
  description = "Account the function is created in, for the same ARNs"
  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}
variable "partition" {
  type        = string
  default     = "aws"
  description = "Partition for the same ARNs"
  validation {
    condition     = contains(["aws", "aws-cn", "aws-us-gov"], var.partition)
    error_message = "partition must be aws, aws-cn or aws-us-gov."
  }
}
