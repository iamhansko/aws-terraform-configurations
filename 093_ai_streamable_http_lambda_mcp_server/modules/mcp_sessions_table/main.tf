# The session store awslabs.mcp_lambda_handler writes to when it is given a table name.
#
# The key and the TTL attribute are not variables, because they are not this module's choice: the library's
# DynamoDBSessionStore writes items keyed session_id and stamps each with expires_at, 24 hours out. A table
# keyed on anything else rejects every put, and a TTL on any other attribute never expires anything - and
# neither shows up before the first MCP request. So the names are written here once, matching the library.
resource "aws_dynamodb_table" "sessions" {
  name         = var.name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "session_id"
  attribute {
    name = "session_id"
    type = "S"
  }
  # The library also checks expires_at itself on every read, so a session past its time is treated as gone
  # in the window - which can be days - before DynamoDB's TTL sweep actually deletes the item.
  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }
  tags = {
    Purpose = var.purpose_tag
  }
}
