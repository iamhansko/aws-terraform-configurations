variable "tables" {
  type = map(object({
    name      = string
    hash_key  = string
    range_key = optional(string)
  }))
  default = {
    items     = { name = "Items", hash_key = "id" }
    inventory = { name = "Inventory", hash_key = "id", range_key = "itemId" }
    location  = { name = "Location", hash_key = "itemId", range_key = "location" }
    users     = { name = "Users", hash_key = "userId" }
    usernames = { name = "Usernames", hash_key = "username" }
    persona   = { name = "Persona", hash_key = "userId", range_key = "detail" }
  }
  description = "Tables, keyed by a label, with their names and key attributes, as the _monolithic template had them. The server reads each name from a DYNAMODB_TABLE_<LABEL> environment variable"

  validation {
    condition     = alltrue([for key in keys(var.tables) : can(regex("^[a-z][a-z0-9_]*$", key))])
    error_message = "tables keys must be lowercase identifiers, because each becomes part of an environment variable name."
  }
  validation {
    condition     = alltrue([for t in values(var.tables) : can(regex("^[a-zA-Z0-9_.-]{3,255}$", t.name))])
    error_message = "each table name must be 3-255 characters of letters, digits and _.-."
  }
}
variable "name_prefix" {
  type        = string
  default     = ""
  description = "Prefix added to every table name. Empty, so the names are the _monolithic template's - which are plain words, unique per account and region, so a second copy of this project in the account needs a prefix"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_.-]{0,64}$", var.name_prefix))
    error_message = "name_prefix must be up to 64 characters of letters, digits and _.-."
  }
}
variable "point_in_time_recovery" {
  type        = bool
  default     = true
  description = "Whether each table keeps 35 days of point-in-time recovery, as the _monolithic template had it"
}
