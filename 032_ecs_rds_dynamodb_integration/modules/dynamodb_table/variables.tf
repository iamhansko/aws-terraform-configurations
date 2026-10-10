variable "name" {
  type        = string
  default     = "appdev-dynamo-table"
  description = "Name of the table, as the _monolithic template had it. A fixed name, so a second copy of this project in one account fails with ResourceInUseException - override it there"
  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]{3,255}$", var.name))
    error_message = "name must be 3-255 characters of letters, digits, dots, underscores and hyphens."
  }
}
variable "billing_mode" {
  type        = string
  default     = "PAY_PER_REQUEST"
  description = "PAY_PER_REQUEST or PROVISIONED. PAY_PER_REQUEST as the template had it, which is also what suits a table that sees a handful of writes during a demo and nothing afterwards - PROVISIONED would additionally require read_capacity and write_capacity here"
  validation {
    condition     = contains(["PAY_PER_REQUEST", "PROVISIONED"], var.billing_mode)
    error_message = "billing_mode must be PAY_PER_REQUEST or PROVISIONED."
  }
}
variable "hash_key" {
  type        = string
  default     = "id"
  description = "Partition key attribute name. Must appear in attributes. \"id\", because it is the one key attribute src/product/main.go puts in its GetItem key - the two have to agree or every read is a ValidationException. Changing it replaces the table"
  validation {
    condition     = length(var.hash_key) > 0
    error_message = "hash_key must not be empty."
  }
}
variable "range_key" {
  type        = string
  default     = null
  description = "Sort key attribute name, or null for a table keyed on hash_key alone. Null, where the _monolithic template declared \"price\": the product application's GetItem names only id, and DynamoDB rejects a key that leaves out an element of a composite primary key with ValidationException, which the handler returns as a 500 - see main.tf. Setting one means changing that call to supply it. Changing it replaces the table"
  validation {
    condition     = var.range_key == null || length(var.range_key) > 0
    error_message = "range_key must be a non-empty attribute name, or null for a table with no sort key."
  }
}
variable "attributes" {
  type        = map(string)
  default     = { id = "S" }
  description = "Key attribute names mapped to their DynamoDB types (S, N or B). Only key and index attributes may be declared; anything else the application writes needs no declaration. A map rather than a list of objects so the attribute block's for_each has statically known keys"
  validation {
    condition     = length(var.attributes) > 0
    error_message = "attributes must declare at least the hash key."
  }
  validation {
    condition     = alltrue([for type in values(var.attributes) : contains(["S", "N", "B"], type)])
    error_message = "attributes values must each be S (string), N (number) or B (binary)."
  }
  validation {
    # A cross-variable condition, because the constraint is about the combination rather than about any one
    # value (rules.md B-1). DynamoDB rejects both halves of the mismatch at apply: a key attribute that is
    # not declared, and a declared attribute that is not part of a key or an index.
    condition     = contains(keys(var.attributes), var.hash_key) && (var.range_key == null || contains(keys(var.attributes), var.range_key))
    error_message = "attributes must declare hash_key, and range_key when it is not null. DynamoDB rejects a key schema naming an undeclared attribute at apply with ValidationException; plan does not check it."
  }
  validation {
    condition     = var.range_key == null ? length(var.attributes) == 1 : length(var.attributes) == 2
    error_message = "attributes must contain exactly the key attributes - one when range_key is null, two otherwise. A declared attribute that is not part of the key schema or a secondary index is rejected at apply with ValidationException, and this module declares no secondary indexes."
  }
}
variable "point_in_time_recovery" {
  type        = bool
  default     = false
  description = "Whether continuous backups are kept for the last 35 days. Off, which is the DynamoDB default and what the template left it at. It bills per GB of table size, which for this table is negligible, but a demo table holding three test items has nothing worth recovering"
}
