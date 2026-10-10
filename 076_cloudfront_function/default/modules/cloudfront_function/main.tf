# One CloudFront Function, published to LIVE, and optionally a key value store associated with it.
#
# The store lives in this module rather than beside the distribution because a store means nothing without
# the function that reads it: it is associated with the function, not with the distribution, and a function
# can be associated with at most one store.
resource "aws_cloudfront_key_value_store" "store" {
  count   = var.key_value_store_name != null ? 1 : 0
  name    = var.key_value_store_name
  comment = "Read by the ${var.name} CloudFront Function"
}
resource "aws_cloudfront_function" "function" {
  name    = var.name
  comment = var.comment
  runtime = var.runtime
  code    = var.code
  # publish = true promotes the code to the LIVE stage on every change. Only LIVE runs at the edge, so
  # without it the distribution keeps executing the previous code - or, on the first apply, the association
  # is rejected because there is no LIVE stage yet.
  publish                      = true
  key_value_store_associations = aws_cloudfront_key_value_store.store[*].arn
}
