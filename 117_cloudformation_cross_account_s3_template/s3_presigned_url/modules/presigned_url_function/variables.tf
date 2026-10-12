variable "function_name" {
  type        = string
  description = "Name of the presigning Lambda function"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,64}$", var.function_name))
    error_message = "function_name must be 1-64 characters of letters, digits, hyphens and underscores."
  }
}
variable "runtime" {
  type        = string
  default     = "python3.14"
  description = "Lambda runtime, as the _monolithic template had it"

  validation {
    condition     = startswith(var.runtime, "python3.")
    error_message = "runtime must be a Python 3 Lambda runtime - the handler is Python."
  }
}
variable "bucket_name" {
  type        = string
  description = "Bucket holding the object to presign"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "bucket_name must be a valid S3 bucket name."
  }
}
variable "object_key" {
  type        = string
  description = "Key of the object to presign. Taken from the module that uploaded it, so the invocation is ordered after the upload"

  validation {
    condition     = length(var.object_key) > 0
    error_message = "object_key must not be empty."
  }
}
variable "object_arn" {
  type        = string
  description = "ARN of the object, which is all the function's role is allowed to read"

  validation {
    condition     = can(regex("^arn:aws[a-zA-Z-]*:s3:::.+/.+$", var.object_arn))
    error_message = "object_arn must be an S3 object ARN (arn:aws:s3:::<bucket>/<key>)."
  }
}
variable "expires_in_seconds" {
  type        = number
  default     = 3600
  description = "Lifetime requested for the URL, as the _monolithic template had it. A request, not a guarantee: the URL also stops working when the Lambda role session that signed it expires, whichever is first"

  validation {
    # SigV4's own ceiling. S3 rejects a presigned URL whose X-Amz-Expires exceeds it.
    condition     = var.expires_in_seconds >= 1 && var.expires_in_seconds <= 604800
    error_message = "expires_in_seconds must be between 1 and 604800 (seven days), the most a SigV4 presigned URL can be valid for."
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
