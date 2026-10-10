variable "function_name" {
  type        = string
  description = "Name of the waiting function"
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]{1,64}$", var.function_name))
    error_message = "function_name must be 1-64 characters of letters, digits, hyphens and underscores."
  }
}
variable "bucket_name" {
  type        = string
  description = "Bucket the object is uploaded to"
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "bucket_name must be a valid S3 bucket name."
  }
}
variable "bucket_arn" {
  type        = string
  description = "ARN of bucket_name. The function may list it, which is what makes S3 answer 404 rather than 403 for a key that does not exist yet"
  validation {
    condition     = can(regex("^arn:aws[a-z-]*:s3:::[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_arn))
    error_message = "bucket_arn must be an S3 bucket ARN (arn:aws:s3:::<bucket>)."
  }
}
variable "object_key" {
  type        = string
  description = "Key of the object to wait for. The function may read this key and no other"
  validation {
    condition     = length(var.object_key) > 0 && !startswith(var.object_key, "/")
    error_message = "object_key must be a non-empty relative key with no leading slash."
  }
}
variable "association_id" {
  type        = string
  description = "ID of the SSM association that checks the upload. Consulted only to stop early when its current run has failed - never to decide that the upload is done, because an association reports Success before its target has picked it up"
  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.association_id))
    error_message = "association_id must be an SSM association ID (a UUID)."
  }
}
variable "association_arn" {
  type        = string
  description = "ARN of association_id, which the function's read-only SSM permissions are scoped to"
  validation {
    condition     = can(regex("^arn:aws[a-z-]*:ssm:[a-z0-9-]+:[0-9]{12}:association/[0-9a-fA-F-]{36}$", var.association_arn))
    error_message = "association_arn must be an SSM association ARN (arn:aws:ssm:<region>:<account>:association/<id>)."
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
variable "timeout_seconds" {
  type        = number
  default     = 900
  description = "How long the apply waits for the object, and therefore the function's timeout: the invocation is the wait, so the two cannot mean different things. At most 900, the longest a Lambda function can run"
  validation {
    condition     = var.timeout_seconds >= 60 && var.timeout_seconds <= 900 && floor(var.timeout_seconds) == var.timeout_seconds
    error_message = "timeout_seconds must be an integer between 60 and 900 - it is the function's timeout, and 900 is the most Lambda accepts."
  }
}
variable "runtime" {
  type        = string
  default     = "python3.13"
  description = "Lambda runtime. The handler uses only boto3, which every Python runtime provides"
  validation {
    condition     = can(regex("^python3\\.[0-9]+$", var.runtime))
    error_message = "runtime must be a Python 3 runtime (e.g. python3.13)."
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
