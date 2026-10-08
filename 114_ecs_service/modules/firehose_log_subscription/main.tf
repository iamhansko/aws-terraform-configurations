data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
# The log group the task's awslogs driver writes to, and the subscription that streams every event in it to
# Firehose as it arrives.
#
# One module because the subscription is meaningless without its group and the group exists here only to be
# subscribed: the task definition takes the group's name from this module's output, so the container writes
# to exactly the group the filter is attached to (rules.md B-5).
resource "aws_cloudwatch_log_group" "log_group" {
  name              = var.log_group_name
  retention_in_days = var.retention_in_days
}
resource "aws_iam_role" "subscription" {
  name_prefix = var.role_name_prefix
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "logs.amazonaws.com" }
      Action    = "sts:AssumeRole"
      # The confused-deputy guard CloudWatch Logs documents for subscription roles. The _monolithic template's
      # trust policy had none, so any log group in any account could have used this role.
      Condition = {
        StringLike = { "aws:SourceArn" = "arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:*" }
      }
    }]
  })
}
# Scoped to the one stream and the one key.
#
# The _monolithic template granted PutRecord on deliverystream/* and Decrypt/GenerateDataKey on key/* - every
# stream and every key in the account - and then attached AmazonKinesisFirehoseFullAccess on top, which
# includes deleting streams. The two inline statements already covered everything the subscription does, so
# the managed policy is gone and the wildcards are replaced with the two ARNs this module is given.
resource "aws_iam_role_policy" "subscription" {
  name = "FirehosePolicy"
  role = aws_iam_role.subscription.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["firehose:PutRecord", "firehose:PutRecordBatch"]
        Resource = var.delivery_stream_arn
      },
      {
        Effect   = "Allow"
        Action   = ["kms:GenerateDataKey", "kms:Decrypt"]
        Resource = var.delivery_stream_kms_key_arn
      },
    ]
  })
}
resource "aws_cloudwatch_log_subscription_filter" "subscription" {
  name                      = var.filter_name
  log_group_name            = aws_cloudwatch_log_group.log_group.name
  destination_arn           = var.delivery_stream_arn
  role_arn                  = aws_iam_role.subscription.arn
  filter_pattern            = var.filter_pattern
  apply_on_transformed_logs = false
  # CloudWatch Logs delivers a test record when the filter is created and rejects the filter if it cannot.
  # role_arn orders this after the role but not after the policy that lets it write, so without this the
  # create races the policy (rules.md D-1).
  depends_on = [aws_iam_role_policy.subscription]
}
