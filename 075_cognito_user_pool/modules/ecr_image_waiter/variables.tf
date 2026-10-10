variable "function_name" {
  type        = string
  description = "Name of the waiting function"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]{1,64}$", var.function_name))
    error_message = "function_name must be 1-64 characters of letters, digits, hyphens and underscores."
  }
}
variable "images" {
  type = map(object({
    repository_name = string
    repository_arn  = string
    image_tag       = string
  }))
  description = "The images to wait for, keyed by a caller-chosen label that the outputs are keyed by too. The function may describe images in these repositories and no others"

  validation {
    condition     = length(var.images) > 0 && alltrue([for label in keys(var.images) : can(regex("^[a-zA-Z0-9_-]+$", label))])
    error_message = "images must not be empty, and its keys must be labels of letters, digits, underscores and hyphens."
  }
  validation {
    condition     = alltrue([for image in values(var.images) : can(regex("^(?:[a-z0-9]+(?:[._-][a-z0-9]+)*/)*[a-z0-9]+(?:[._-][a-z0-9]+)*$", image.repository_name))])
    error_message = "Each repository_name must be a valid ECR repository name."
  }
  validation {
    condition     = alltrue([for image in values(var.images) : can(regex("^arn:aws[a-z-]*:ecr:[a-z0-9-]+:[0-9]{12}:repository/.+$", image.repository_arn))])
    error_message = "Each repository_arn must be an ECR repository ARN (arn:aws:ecr:<region>:<account>:repository/<name>)."
  }
  validation {
    condition     = alltrue([for image in values(var.images) : can(regex("^[a-zA-Z0-9_][a-zA-Z0-9_.-]{0,127}$", image.image_tag))])
    error_message = "Each image_tag must be a valid image tag: up to 128 letters, digits, underscores, periods and hyphens, not starting with a period or hyphen."
  }
}
variable "association_id" {
  type        = string
  description = "ID of the SSM association that pushes the images. Consulted only to stop early when its current run has failed - never to decide that the pushes are done, because an association reports Success before its target has registered"

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
variable "timeout_seconds" {
  type        = number
  default     = 900
  description = "How long the apply waits for the images, and therefore the function's timeout: the invocation is the wait, so the two cannot mean different things. At most 900, the longest a Lambda function can run"

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
