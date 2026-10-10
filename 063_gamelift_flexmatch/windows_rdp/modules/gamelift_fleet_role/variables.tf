variable "role_name_prefix" {
  type        = string
  default     = "gamelift-flexmatch-fleet-"
  description = "Prefix for the generated role name. The _monolithic template left the role unnamed, so the provider generated one; a prefix keeps that uniqueness and makes the role findable"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,38}$", var.role_name_prefix))
    error_message = "role_name_prefix must be 1-38 characters of letters, digits and +=,.@_- (IAM's name_prefix limit leaves the rest of the 64 characters for the generated suffix)."
  }
}
variable "game_result_queue_arn" {
  type        = string
  description = "ARN of the queue the game server sends results to, the only resource this role is granted"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:sqs:", var.game_result_queue_arn))
    error_message = "game_result_queue_arn must be an SQS queue ARN."
  }
}
variable "additional_policy_arns" {
  type        = list(string)
  default     = []
  description = "Managed policies attached on top of the scoped grant. Empty by default; [\"arn:aws:iam::aws:policy/AmazonSQSFullAccess\"] reproduces the _monolithic template's breadth"

  validation {
    condition     = alltrue([for arn in var.additional_policy_arns : can(regex("^arn:aws[a-z-]*:iam::", arn))])
    error_message = "additional_policy_arns must contain valid IAM policy ARNs."
  }
}
