# The matchmaker's notification target. FlexMatch publishes every matchmaking
# event here - MatchmakingSearching, PotentialMatchCreated,
# MatchmakingSucceeded and the rest - and game-match-event, subscribed below,
# picks out MatchmakingSucceeded and writes each player's connection info into
# the player table for the game client to poll through /matchstatus.
resource "aws_sns_topic" "match_events" {
  name = var.topic_name
}
# Two statements, the first reproduced and the second scoped.
#
# AllowSnsActions is the policy SNS writes by default: every action, to any AWS
# principal, conditioned on AWS:SourceOwner being this account. Whether that
# would admit a publish from the gamelift.amazonaws.com service principal
# depends on how SNS fills AWS:SourceOwner for a service caller, which neither
# the SNS nor the FlexMatch documentation states and which only a live publish
# could settle. It does not need settling: the FlexMatch guide's own grant is
# the second statement.
#
# AllowSnsPublish was already in the _monolithic template, granting
# gamelift.amazonaws.com SNS:Publish with no condition at all - any matchmaking
# configuration in any account could publish into this topic, the
# confused-deputy shape. The FlexMatch guide's SNS tutorial scopes it with
# ArnLike aws:SourceArn on the configuration; aws:SourceAccount is added on top
# so the grant still means "this account" if the source ARN is ever widened to
# a wildcard.
#
# The configuration ARN is assembled by the caller from its name rather than
# read off the configuration resource, because the configuration in turn names
# this topic as its notification target - reading it would make the two depend
# on each other.
resource "aws_sns_topic_policy" "match_events" {
  # A single topic ARN string, not the list CloudFormation's
  # AWS::SNS::TopicPolicy Topics property takes. jsonencode([...]) here would
  # pass validate and plan - the attribute is a string either way - and fail
  # as an SNS API error during apply (rules.md A-3).
  arn = aws_sns_topic.match_events.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "SnsTopicPolicy"
    Statement = [
      {
        Sid    = "AllowSnsActions"
        Effect = "Allow"
        Principal = {
          AWS = "*"
        }
        Action = [
          "SNS:GetTopicAttributes",
          "SNS:SetTopicAttributes",
          "SNS:AddPermission",
          "SNS:RemovePermission",
          "SNS:DeleteTopic",
          "SNS:Subscribe",
          "SNS:ListSubscriptionsByTopic",
          "SNS:Publish",
        ]
        Resource = aws_sns_topic.match_events.arn
        Condition = {
          StringEquals = {
            "AWS:SourceOwner" = var.account_id
          }
        }
      },
      {
        Sid    = "AllowSnsPublish"
        Effect = "Allow"
        Principal = {
          Service = "gamelift.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.match_events.arn
        Condition = {
          ArnLike = {
            "aws:SourceArn" = var.publisher_source_arns
          }
          StringEquals = {
            "aws:SourceAccount" = var.account_id
          }
        }
      },
    ]
  })
}
resource "aws_sns_topic_subscription" "lambda" {
  for_each  = var.lambda_subscribers
  topic_arn = aws_sns_topic.match_events.arn
  protocol  = "lambda"
  endpoint  = each.value.function_arn
}
# SNS invokes the function with its own service principal, so the function's
# resource policy has to admit it; scoped to this topic.
resource "aws_lambda_permission" "lambda" {
  for_each      = var.lambda_subscribers
  action        = "lambda:InvokeFunction"
  function_name = each.value.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.match_events.arn
}
