variable "name" {
  type        = string
  description = "Table name. The root pins it to GomokuPlayerInfo, because four of the six Lambda handlers name that table literally"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_.-]{3,255}$", var.name))
    error_message = "name must be 3-255 characters of letters, digits, underscores, hyphens and dots."
  }
}
variable "hash_key" {
  type        = string
  default     = "PlayerName"
  description = "Partition key attribute. PlayerName is what every handler keys get_item and update_item on, and what game-rank-update reads out of the stream record's Keys"

  validation {
    condition     = length(var.hash_key) > 0
    error_message = "hash_key must not be empty."
  }
}
variable "billing_mode" {
  type        = string
  default     = "PAY_PER_REQUEST"
  description = "Billing mode, as the _monolithic template had it. PROVISIONED would also need read and write capacity, which this module does not set"

  validation {
    condition     = contains(["PAY_PER_REQUEST"], var.billing_mode)
    error_message = "billing_mode must be PAY_PER_REQUEST - this module sets no read or write capacity, which PROVISIONED requires."
  }
}
variable "stream_view_type" {
  type        = string
  default     = "NEW_AND_OLD_IMAGES"
  description = "What the stream carries. game-rank-update reads NewImage.Score from each record, so the stream must include new images"

  validation {
    condition     = contains(["NEW_IMAGE", "NEW_AND_OLD_IMAGES"], var.stream_view_type)
    error_message = "stream_view_type must be NEW_IMAGE or NEW_AND_OLD_IMAGES, because game-rank-update reads NewImage from every record; KEYS_ONLY and OLD_IMAGE leave it nothing to score."
  }
}
