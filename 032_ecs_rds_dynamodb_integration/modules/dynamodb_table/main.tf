# The product application's store: one declared attribute, id as the hash key and no range key, on-demand
# billing.
#
# A deliberate departure from the _monolithic template, which declared price as a range key beside id. That
# is what made the application's read path fail. src/product/main.go reads a product back by id alone:
#
#   key := map[string]types.AttributeValue{"id": &types.AttributeValueMemberS{Value: id}}
#
# and a GetItem against a composite primary key has to name both elements, so DynamoDB answered every read
# with ValidationException ("The provided key element does not match the schema") and the handler turned it
# into "Internal Server Error". The table was the thing to change rather than the call, because a product
# keyed on price as well as id is not one product: a second POST of the same id at a new price would have
# written a second item beside the first, and nothing the application exposes takes a price to say which
# of the two it means. The template's own TABLE_INDEX_NAME value, "id", names the same key.
#
# price is still written on every item; it is an ordinary attribute now, and DynamoDB needs no declaration
# for it. Changing hash_key or range_key replaces the table, which is what applying this does to a table
# created from the template's shape - the items in it go with it.
resource "aws_dynamodb_table" "dynamo_table" {
  name         = var.name
  billing_mode = var.billing_mode
  hash_key     = var.hash_key
  range_key    = var.range_key
  # A declared attribute is only the key schema's type declaration - DynamoDB is schemaless for everything
  # else, so name and price are stored without appearing here. Declaring an attribute that is not part of a
  # key or an index is rejected at apply with ValidationException.
  dynamic "attribute" {
    for_each = var.attributes
    content {
      name = attribute.key
      type = attribute.value
    }
  }
  point_in_time_recovery {
    enabled = var.point_in_time_recovery
  }
}
