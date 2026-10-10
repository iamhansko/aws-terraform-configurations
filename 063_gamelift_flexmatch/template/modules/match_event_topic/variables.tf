variable "name" {
  type        = string
  default     = "gomoku-match-topic"
  description = "Topic name, as the _monolithic template had it. Nothing hard-codes it: the matchmaking configuration is given the topic's ARN"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+$", var.name)) && length(var.name) <= 256
    error_message = "name must be 1-256 characters of letters, digits, hyphens and underscores (a standard topic, so no .fifo suffix)."
  }
}
variable "account_id" {
  type        = string
  description = "Account that owns the topic and the matchmaking configuration, for the policy conditions"

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}
variable "publisher_source_arn" {
  type        = string
  description = "ARN (ArnLike pattern) of the FlexMatch matchmaking configuration allowed to publish here. The gamelift.amazonaws.com statement is scoped to it so that no other account's matchmaker can use this topic as its notification target"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:gamelift:[a-z0-9-]+:[0-9*]*:matchmakingconfiguration/.+$", var.publisher_source_arn))
    error_message = "publisher_source_arn must be a GameLift matchmaking configuration ARN, arn:<partition>:gamelift:<region>:<account or *>:matchmakingconfiguration/<name>."
  }
}
variable "subscriber_function_arns" {
  type        = map(string)
  default     = {}
  description = "Lambda functions subscribed to the topic, keyed by a caller-chosen label. A map because the ARNs are another module's output and unknown at plan (rules.md B-8)"

  validation {
    condition     = alltrue([for label in keys(var.subscriber_function_arns) : can(regex("^[a-zA-Z0-9_-]+$", label))])
    error_message = "subscriber_function_arns keys must be labels of letters, digits, hyphens and underscores."
  }
  validation {
    condition     = alltrue([for arn in values(var.subscriber_function_arns) : can(regex("^arn:aws[a-z-]*:lambda:", arn))])
    error_message = "subscriber_function_arns must contain Lambda function ARNs."
  }
}
