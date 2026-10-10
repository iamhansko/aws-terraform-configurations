# The topic the state machine's two notification states publish to.
#
# Worth knowing what it does not do by default: with no subscriptions, a publish succeeds and the message is
# discarded. The _monolithic template created exactly that, so both of its notification states reported
# success and nobody was notified - which is indistinguishable from working.
resource "aws_sns_topic" "topic" {
  name         = var.name
  display_name = var.display_name
}
resource "aws_sns_topic_subscription" "email" {
  for_each = toset(var.email_subscriptions)

  topic_arn = aws_sns_topic.topic.arn
  protocol  = "email"
  endpoint  = each.value
  # No confirmation_timeout_in_minutes and no endpoint_auto_confirms: an email subscription cannot be
  # auto-confirmed. It is created pending and stays pending until the address owner clicks the link, which
  # means terraform apply finishes with a subscription that does not yet deliver.
}
resource "aws_sns_topic_policy" "publishers" {
  count = length(var.publisher_role_arns) == 0 ? 0 : 1

  arn = aws_sns_topic.topic.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowNamedPublishers"
      Effect    = "Allow"
      Principal = { AWS = var.publisher_role_arns }
      Action    = "sns:Publish"
      Resource  = aws_sns_topic.topic.arn
    }]
  })
}
