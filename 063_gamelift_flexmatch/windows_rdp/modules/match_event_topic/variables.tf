variable "topic_name" {
  type        = string
  default     = "gomoku-match-topic"
  description = "Name of the topic, as the _monolithic template had it. Unique per account and region, and not read by any code - the matchmaker is given the ARN"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,256}$", var.topic_name))
    error_message = "topic_name must be 1-256 characters of letters, digits, hyphens and underscores (a standard topic - FlexMatch's guide recommends against FIFO for notifications)."
  }
}
variable "account_id" {
  type        = string
  description = "Account that owns the topic and the matchmaker, used in both statements' account conditions"

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}
variable "publisher_source_arns" {
  type        = list(string)
  description = "Matchmaking configuration ARNs allowed to publish as gamelift.amazonaws.com. Assembled by the caller from the configuration names rather than read off the configurations, which name this topic and so cannot be referenced from here without a cycle"

  validation {
    condition     = length(var.publisher_source_arns) > 0 && alltrue([for arn in var.publisher_source_arns : can(regex("^arn:aws[a-z-]*:gamelift:[a-z0-9-]+:[0-9]{12}:matchmakingconfiguration/", arn))])
    error_message = "publisher_source_arns must contain at least one GameLift matchmaking configuration ARN (arn:aws:gamelift:<region>:<account>:matchmakingconfiguration/<name>)."
  }
}
variable "lambda_subscribers" {
  type = map(object({
    function_arn  = string
    function_name = string
  }))
  default     = {}
  description = "Functions subscribed to the topic, keyed by a caller-chosen label. A map with literal keys because the ARNs are another module's output and unknown at plan time (rules.md B-8)"

  validation {
    condition     = alltrue([for label in keys(var.lambda_subscribers) : can(regex("^[a-zA-Z0-9._-]+$", label))])
    error_message = "lambda_subscribers keys must be non-empty labels of letters, digits, dots, underscores or hyphens."
  }
}
