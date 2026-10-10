variable "role_name_prefix" {
  type        = string
  description = "Prefix for the role's name. The provider appends a unique suffix"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]+$", var.role_name_prefix)) && length(var.role_name_prefix) <= 38
    error_message = "role_name_prefix must be 1-38 characters from the set IAM accepts for a role name (name_prefix is capped at 38)."
  }
}
variable "game_result_queue_arn" {
  type        = string
  description = "ARN of the queue the game server reports results to - the one resource this role's grant covers"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:sqs:[a-z0-9-]+:[0-9]{12}:.+$", var.game_result_queue_arn))
    error_message = "game_result_queue_arn must be an SQS queue ARN."
  }
}
variable "additional_policy_arns" {
  type        = list(string)
  default     = []
  description = "Managed policy ARNs attached on top of the scoped queue grant. Empty by default; the _monolithic template's AmazonSQSFullAccess is one entry away here"

  validation {
    condition     = alltrue([for arn in var.additional_policy_arns : can(regex("^arn:aws[a-z-]*:iam::", arn))])
    error_message = "additional_policy_arns must contain valid IAM policy ARNs."
  }
}
