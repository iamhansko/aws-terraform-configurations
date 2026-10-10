# The game server's tables. One resource with for_each rather than six copies, because they differ only in
# name and keys (rules.md B-7). The keys of var.tables are literal, so the addresses are known at plan.
resource "aws_dynamodb_table" "table" {
  for_each     = var.tables
  name         = "${var.name_prefix}${each.value.name}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = each.value.hash_key
  range_key    = each.value.range_key
  # Every key attribute is a string in this schema, as the _monolithic template declared them.
  dynamic "attribute" {
    for_each = compact([each.value.hash_key, each.value.range_key])
    content {
      name = attribute.value
      type = "S"
    }
  }
  point_in_time_recovery {
    enabled = var.point_in_time_recovery
  }
}
