variable "table_name" {
  type        = string
  default     = "GomokuPlayerInfo"
  description = "Name of the player table. Load-bearing: GameResultProcessing.py, MatchEvent.py, MatchRequest.py and MatchStatus.py in Lambda/code.zip all open dynamodb.Table('GomokuPlayerInfo') by that literal name, and none of them reads it from the environment"

  validation {
    condition     = var.table_name == "GomokuPlayerInfo"
    error_message = "table_name must stay GomokuPlayerInfo. The handlers in the sample repository's Lambda/code.zip hard-code that name, so any other value creates a table no function reads and leaves every one of them calling a table that does not exist. To rename it, rebuild code.zip with the new name first and then relax this validation."
  }
}
variable "stream_view_type" {
  type        = string
  default     = "NEW_AND_OLD_IMAGES"
  description = "What each stream record carries, as the _monolithic template had it. Scoring.py reads NewImage, so the type must include the new image"

  validation {
    condition     = contains(["NEW_IMAGE", "NEW_AND_OLD_IMAGES"], var.stream_view_type)
    error_message = "stream_view_type must be NEW_IMAGE or NEW_AND_OLD_IMAGES. KEYS_ONLY and OLD_IMAGE would leave game-rank-update without the NewImage it reads the score from."
  }
}
