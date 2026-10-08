variable "tables" {
  type = map(object({
    hash_key       = string
    hash_key_type  = optional(string, "S")
    range_key      = optional(string)
    range_key_type = optional(string, "S")
  }))
  description = <<-DESC
    The tables to create, keyed by a short logical name that becomes part of the table name.

    This replaces six separate aws_dynamodb_table resources in the _monolithic template that differed only
    in their name and their key schema. The schema belongs in a typed variable rather than in six resource
    bodies because that is what makes the difference between the tables reviewable in one place - reading
    the conversion, it takes six scrolls to establish that location is keyed on itemId and persona on
    userId.

    Keys are literal strings in configuration, so they are known at plan time and are usable as the
    for_each of the table resource (rules.md B-8). They are also what the caller's instance turns into
    DYNAMODB_TABLE_<KEY> environment variables, which is why the windows_ec2 module constrains their
    character set further than DynamoDB does.
  DESC

  validation {
    condition     = length(var.tables) > 0
    error_message = "tables must not be empty."
  }
  validation {
    # DynamoDB's own table name character set. Validated on the key rather than
    # on the assembled name because the key is the part a caller writes.
    condition     = alltrue([for key in keys(var.tables) : can(regex("^[a-zA-Z0-9_.-]+$", key))])
    error_message = "tables keys must contain only letters, digits, underscores, dots and hyphens, because each one is interpolated into a DynamoDB table name."
  }
  validation {
    condition     = alltrue([for table in values(var.tables) : length(table.hash_key) > 0])
    error_message = "every table must declare a non-empty hash_key."
  }
  validation {
    condition = alltrue([for table in values(var.tables) :
      contains(["S", "N", "B"], table.hash_key_type) && contains(["S", "N", "B"], table.range_key_type)
    ])
    error_message = "hash_key_type and range_key_type must be S, N or B - the three scalar types DynamoDB allows in a key schema."
  }
  validation {
    condition     = alltrue([for table in values(var.tables) : table.range_key == null || length(table.range_key) > 0])
    error_message = "range_key must be a non-empty attribute name, or null for a table with no sort key."
  }
  validation {
    # A table whose two key attributes are the same name collapses to a single
    # attribute definition, and DynamoDB rejects it at apply with
    # ValidationException: Number of attributes in KeySchema does not exactly
    # match number of attributes defined in AttributeDefinitions - a message that
    # does not name the table or the attribute.
    condition     = alltrue([for table in values(var.tables) : table.range_key == null || table.range_key != table.hash_key])
    error_message = "range_key must differ from hash_key. Naming the same attribute twice is accepted by terraform plan and rejected by DynamoDB at apply with a ValidationException that names neither the table nor the attribute."
  }
}
variable "name_prefix" {
  type        = string
  default     = "spirit-of-kiro-"
  description = "Prepended to each table key to form the table name. CloudFormation generated these names automatically; Terraform requires them, so the _monolithic template derived them from the stack name and this reproduces that"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_.-]*$", var.name_prefix))
    error_message = "name_prefix must contain only letters, digits, underscores, dots and hyphens, the character set DynamoDB allows in a table name."
  }
}
variable "name_suffix" {
  type        = string
  default     = "-table"
  description = "Appended to each table key to form the table name, reproducing the -table ending the _monolithic template gave all six"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_.-]*$", var.name_suffix))
    error_message = "name_suffix must contain only letters, digits, underscores, dots and hyphens, the character set DynamoDB allows in a table name."
  }
}
variable "billing_mode" {
  type        = string
  default     = "PAY_PER_REQUEST"
  description = "Capacity mode for every table, as the _monolithic template had it. PAY_PER_REQUEST is why none of these tables declares read or write capacity - under PROVISIONED the provider requires both and apply fails without them"

  validation {
    condition     = contains(["PAY_PER_REQUEST", "PROVISIONED"], var.billing_mode)
    error_message = "billing_mode must be PAY_PER_REQUEST or PROVISIONED. This module declares no read_capacity or write_capacity, so PROVISIONED would fail at apply - a table created that way needs those arguments added here first."
  }
}
variable "point_in_time_recovery_enabled" {
  type        = bool
  default     = true
  description = "Whether continuous backups are on, as the _monolithic template had them. True is the safer default and it is billed by stored size, which is negligible for a demo; false removes that charge and the ability to restore"
}
variable "deletion_protection_enabled" {
  type        = bool
  default     = false
  description = "Whether DynamoDB refuses to delete the tables. False, which the _monolithic template left at the default, and deliberately so for a demo - true makes terraform destroy stop with ValidationException on the first table and leave the rest of the project half torn down"
}
variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to every table. Empty by default, which is what the _monolithic template produced - the tables carried no tags at all"

  validation {
    condition     = alltrue([for key in keys(var.tags) : length(key) > 0])
    error_message = "tags keys must not be empty."
  }
}
