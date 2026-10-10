variable "rule_set_name" {
  type        = string
  default     = "gomoku-matchmaking-rule"
  description = "Name of the rule set, as the _monolithic template had it. Unique per account and region. Not read by any code - the configuration references it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9.-]{1,128}$", var.rule_set_name))
    error_message = "rule_set_name must be 1-128 characters of letters, digits, dots and hyphens."
  }
}
variable "rule_set" {
  type = object({
    ruleLanguageVersion = string
    playerAttributes = list(object({
      name    = string
      type    = string
      default = number
    }))
    teams = list(object({
      name       = string
      minPlayers = number
      maxPlayers = number
    }))
    rules = list(object({
      name           = string
      type           = string
      measurements   = list(string)
      referenceValue = string
      operation      = optional(string)
      maxDistance    = optional(number)
    }))
    expansions = list(object({
      target = string
      steps = list(object({
        waitTimeSeconds = number
        value           = number
      }))
    }))
  })
  description = "The FlexMatch rule set document, in FlexMatch's own key names. Typed to the shape this project's rule set uses - number player attributes, comparison and distance rules - rather than to the whole rule language"

  validation {
    condition     = var.rule_set.ruleLanguageVersion == "1.0"
    error_message = "rule_set.ruleLanguageVersion must be 1.0, the only version FlexMatch defines."
  }
  validation {
    condition     = length(var.rule_set.teams) > 0 && alltrue([for t in var.rule_set.teams : t.minPlayers >= 1 && t.minPlayers <= t.maxPlayers])
    error_message = "rule_set.teams must contain at least one team, and each team must have 1 <= minPlayers <= maxPlayers."
  }
  validation {
    condition     = alltrue([for r in var.rule_set.rules : (r.type == "comparison" && r.operation != null) || (r.type == "distance" && r.maxDistance != null)])
    error_message = "rule_set.rules entries must be a comparison rule with an operation or a distance rule with a maxDistance - the two rule types this variable's type describes."
  }
}
variable "configuration_name" {
  type        = string
  default     = "GomokuMatchConfig"
  description = "Name of the matchmaking configuration. Load-bearing: MatchRequest.py in Lambda/code.zip calls start_matchmaking(ConfigurationName='GomokuMatchConfig') with that literal, not from the environment"

  validation {
    condition     = var.configuration_name == "GomokuMatchConfig"
    error_message = "configuration_name must stay GomokuMatchConfig. MatchRequest.py in the sample repository's Lambda/code.zip hard-codes it, so any other name gives a matchmaker no request ever reaches, and every match request returns MatchError. Rebuild code.zip with the new name before relaxing this."
  }
}
variable "acceptance_required" {
  type        = bool
  default     = false
  description = "Whether players must accept a proposed match, as the _monolithic template had it. False: nothing in the game client answers an acceptance prompt"
}
variable "request_timeout_seconds" {
  type        = number
  default     = 60
  description = "How long a ticket may search before it times out, as the _monolithic template had it. Long enough for the rule set's last expansion, at 30 seconds, to take effect"

  validation {
    condition     = var.request_timeout_seconds >= 1 && var.request_timeout_seconds <= 43200
    error_message = "request_timeout_seconds must be between 1 and 43200."
  }
}
variable "game_session_queue_arns" {
  type        = list(string)
  description = "Game session queues a completed match is placed through"

  validation {
    condition     = length(var.game_session_queue_arns) > 0 && alltrue([for arn in var.game_session_queue_arns : can(regex("^arn:aws[a-z-]*:gamelift:", arn))])
    error_message = "game_session_queue_arns must contain at least one GameLift game session queue ARN - a WITH_QUEUE matchmaker places matches through one."
  }
}
variable "notification_target" {
  type        = string
  description = "SNS topic FlexMatch publishes matchmaking events to. game-match-event is subscribed to it and is the only path by which a client learns where its game is"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:sns:", var.notification_target))
    error_message = "notification_target must be an SNS topic ARN."
  }
}
