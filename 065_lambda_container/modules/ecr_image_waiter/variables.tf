variable "function_name" {
  type        = string
  description = "Name of the waiting function"
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]{1,64}$", var.function_name))
    error_message = "function_name must be 1-64 characters of letters, digits, hyphens and underscores."
  }
}
variable "repository_name" {
  type        = string
  description = "Repository the workbench pushes the image to"
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9._/-]{1,255}$", var.repository_name))
    error_message = "repository_name must start with a lowercase letter or digit and contain only lowercase letters, digits and . _ / -."
  }
}
variable "repository_arn" {
  type        = string
  description = "ARN of repository_name, which the function's one ECR permission is scoped to"
  validation {
    condition     = can(regex("^arn:aws[a-z-]*:ecr:[a-z0-9-]+:[0-9]{12}:repository/[a-z0-9._/-]+$", var.repository_arn))
    error_message = "repository_arn must be an ECR repository ARN (arn:aws:ecr:<region>:<account>:repository/<name>)."
  }
}
variable "image_tag" {
  type        = string
  description = "Tag to wait for - the one the workbench pushes"
  validation {
    condition     = can(regex("^[A-Za-z0-9_][A-Za-z0-9._-]{0,127}$", var.image_tag))
    error_message = "image_tag must be a valid container image tag."
  }
}
variable "image_uri" {
  type        = string
  description = "The reference the caller creates its function from. Handed back out of the invocation's result, which is what makes the caller wait"
  validation {
    condition     = can(regex("^[0-9]{12}\\.dkr\\.ecr\\.[a-z0-9-]+\\.amazonaws\\.com(\\.cn)?/[a-z0-9._/-]+:[A-Za-z0-9_][A-Za-z0-9._-]{0,127}$", var.image_uri))
    error_message = "image_uri must be a tagged private ECR image reference."
  }
  validation {
    # About the combination, so a cross-variable condition (rules.md B-1). The function waits on
    # repository_name and image_tag and hands back image_uri; if they named different images, the wait would end
    # on one and CreateFunction would still fail on the other.
    condition     = endswith(var.image_uri, "/${var.repository_name}:${var.image_tag}")
    error_message = "image_uri must end with /<repository_name>:<image_tag>, so the image this module waits for is the one the caller is created from."
  }
}
variable "association_id" {
  type        = string
  description = "ID of the SSM association that checks the push. Consulted only to stop early when its current run has failed - never to decide that the push is done, because an association reports Success before its target has picked it up"
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
  description = "How long the apply waits for the image, and therefore the function's timeout: the invocation is the wait, so the two cannot mean different things. At most 900, the longest a Lambda function can run"
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
