variable "rule_set_name" {
  type        = string
  default     = "gomoku-matchmaking-rule"
  description = "Name of the matchmaking rule set, as the _monolithic template had it. Unique per account and region"

  validation {
    condition     = can(regex("^[a-zA-Z0-9.-]+$", var.rule_set_name)) && length(var.rule_set_name) <= 128
    error_message = "rule_set_name must be 1-128 letters, digits, hyphens and dots."
  }
}
variable "rule_set_body" {
  type        = string
  description = "The rule set as a JSON document. The root renders it with jsonencode from an HCL object, so it is valid JSON by construction; FlexMatch validates the rules themselves when the rule set is created"

  validation {
    condition     = can(jsondecode(var.rule_set_body)) && length(var.rule_set_body) <= 65535
    error_message = "rule_set_body must be a JSON document of at most 65535 characters."
  }
}
variable "configuration_name" {
  type        = string
  default     = "GomokuMatchConfig"
  description = "Name of the matchmaking configuration. The root pins it to GomokuMatchConfig, because MatchRequest.py calls start_matchmaking(ConfigurationName='GomokuMatchConfig') literally"

  validation {
    condition     = can(regex("^[a-zA-Z0-9.-]+$", var.configuration_name)) && length(var.configuration_name) <= 128
    error_message = "configuration_name must be 1-128 letters, digits, hyphens and dots."
  }
}
variable "request_timeout_seconds" {
  type        = number
  default     = 60
  description = "How long a matchmaking ticket may stay in progress before it times out, as the _monolithic template had it. The rule set's expansions relax the skill distance at 10, 20 and 30 seconds, so the last step needs this to be above 30"

  validation {
    condition     = var.request_timeout_seconds >= 1 && var.request_timeout_seconds <= 43200
    error_message = "request_timeout_seconds must be between 1 and 43200."
  }
}
variable "acceptance_required" {
  type        = bool
  default     = false
  description = "Whether matched players must accept a proposed match. False as the _monolithic template had it - the game client has no acceptance step, so true would leave every match waiting for an AcceptMatch call that never comes"
}
variable "game_session_queue_arns" {
  type        = list(string)
  description = "Game session queues the matchmaker places matches through. Not iterated, so another module's output is fine here"

  validation {
    condition     = length(var.game_session_queue_arns) > 0 && alltrue([for arn in var.game_session_queue_arns : can(regex("^arn:aws[a-z-]*:gamelift:", arn))])
    error_message = "game_session_queue_arns must contain at least one GameLift game session queue ARN."
  }
}
variable "notification_topic_arn" {
  type        = string
  description = "SNS topic FlexMatch publishes matchmaking events to. game-match-event subscribes to it, and it is the only path by which a matched player's connection details reach the table game-match-status reads"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:sns:[a-z0-9-]+:[0-9]{12}:.+$", var.notification_topic_arn))
    error_message = "notification_topic_arn must be an SNS topic ARN."
  }
}
