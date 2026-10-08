# One module that creates all six tables with for_each, rather than a
# single-table module the root instantiates six times.
#
# The choice is not obvious, and the argument against it is rules.md C-4, which
# insists every EKS add-on gets its own module. That rule gives three reasons,
# and it is worth checking each against these tables rather than applying the
# shape by analogy:
#
#   1. "Creation order differs per add-on." It does not here. None of these six
#      tables depends on anything but the account, and nothing depends on one
#      table and not another - the game server reads all six from its
#      environment. There is no ordering to express, so there is nothing for six
#      module blocks to express it with.
#   2. "Versioning and blast radius are independent." Also absent. An add-on has
#      a version AWS releases on its own schedule; a DynamoDB table has no such
#      attribute. These six are created together, destroyed together, and never
#      upgraded.
#   3. "The configuration schema differs completely per add-on." The opposite is
#      true: all six are the same shape - PAY_PER_REQUEST, point-in-time
#      recovery, a string hash key and sometimes a string range key. That
#      sameness is exactly what a typed map variable captures.
#
# What the single module buys concretely: the caller gets one map(string) of
# logical name to table name to hand to the instance, instead of assembling
# { for key, instance in module.tables : key => instance.table_name } in the
# root; and the root carries one depends_on edge to the network module rather
# than six, which keeps the rules.md D-3 reachability graph readable.
#
# Reconsider this if a table ever grows something the others do not have - a
# stream feeding a Lambda, a TTL attribute, a global secondary index with its own
# ordering. At that point reason 3 starts to apply and the typed object here
# would be mostly optional fields that are null for five of six entries.
locals {
  # The attribute definitions DynamoDB requires alongside the key schema, derived
  # from the keys rather than listed a second time. The conversion wrote both out
  # per table, which is where a table can end up declaring an attribute it does
  # not key on - DynamoDB rejects that with ValidationException, because
  # AttributeDefinitions may contain only attributes used in a key or an index.
  table_attributes = {
    for key, table in var.tables : key => merge(
      { (table.hash_key) = table.hash_key_type },
      table.range_key == null ? {} : { (table.range_key) = table.range_key_type },
    )
  }
  table_names = { for key in keys(var.tables) : key => "${var.name_prefix}${key}${var.name_suffix}" }
}
resource "aws_dynamodb_table" "table" {
  for_each = var.tables

  name         = local.table_names[each.key]
  billing_mode = var.billing_mode
  hash_key     = each.value.hash_key
  range_key    = each.value.range_key

  dynamic "attribute" {
    for_each = local.table_attributes[each.key]
    content {
      name = attribute.key
      type = attribute.value
    }
  }
  point_in_time_recovery {
    enabled = var.point_in_time_recovery_enabled
  }
  deletion_protection_enabled = var.deletion_protection_enabled

  # No Name tag, unlike the other modules here. A DynamoDB table is addressed by
  # its name everywhere - console, CLI, the game server's environment - so a tag
  # repeating it adds nothing. Empty by default, which is what the _monolithic
  # template produced; this is an extension point, not a divergence.
  tags = var.tags

  lifecycle {
    # DynamoDB's table name limit is 255 characters and its minimum is 3. The
    # name is assembled from three variables, so neither the prefix nor the key
    # alone can be validated against the limit - this is the only place the whole
    # string exists (rules.md B-1 puts the check at plan time; without it the
    # failure is a ValidationException partway through creating six tables, with
    # some already made).
    precondition {
      condition     = length(local.table_names[each.key]) >= 3 && length(local.table_names[each.key]) <= 255
      error_message = "Assembled table name must be 3-255 characters. name_prefix, the table key and name_suffix together exceed what DynamoDB accepts."
    }
  }
}
