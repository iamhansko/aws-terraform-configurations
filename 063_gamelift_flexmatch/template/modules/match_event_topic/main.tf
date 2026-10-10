# FlexMatch publishes every matchmaking event here, and game-match-event writes the game session's address into
# the player table on MatchmakingSucceeded - which is the only way game-match-status ever has an answer for the
# client.
resource "aws_sns_topic" "topic" {
  name = var.name
}
resource "aws_sns_topic_policy" "topic_policy" {
  # A single topic ARN string, not the list CloudFormation's AWS::SNS::TopicPolicy Topics property takes. The
  # attribute is a string either way, so validate and plan pass and the mistake only shows as an SNS error
  # during apply (rules.md A-3).
  arn = aws_sns_topic.topic.arn
  policy = jsonencode({
    Version = "2008-10-17"
    Id      = "SnsTopicPolicy"
    Statement = [
      {
        # The SNS console's default statement, reproduced from the _monolithic template: principals of the
        # owning account may manage and publish to the topic.
        Sid    = "AllowSnsActions"
        Effect = "Allow"
        Principal = {
          AWS = "*"
        }
        Action   = ["SNS:GetTopicAttributes", "SNS:SetTopicAttributes", "SNS:AddPermission", "SNS:RemovePermission", "SNS:DeleteTopic", "SNS:Subscribe", "SNS:ListSubscriptionsByTopic", "SNS:Publish"]
        Resource = aws_sns_topic.topic.arn
        Condition = {
          StringEquals = {
            "AWS:SourceOwner" = var.account_id
          }
        }
      },
      {
        # FlexMatch publishes as the service principal gamelift.amazonaws.com, and the FlexMatch guide's topic
        # policy grants that principal in a statement of its own on top of the console default above - it does
        # not rely on the default's AWS "*" plus AWS:SourceOwner. The _monolithic template had this statement
        # with no condition at all, so any GameLift matchmaker in any account that learned the ARN could publish
        # here. Scoped now as the guide scopes it (aws:SourceArn on the configuration), plus aws:SourceAccount.
        Sid    = "AllowGameLiftPublish"
        Effect = "Allow"
        Principal = {
          Service = "gamelift.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.topic.arn
        Condition = {
          ArnLike = {
            "aws:SourceArn" = var.publisher_source_arn
          }
          StringEquals = {
            "aws:SourceAccount" = var.account_id
          }
        }
      },
    ]
  })
}
resource "aws_lambda_permission" "subscriber" {
  for_each      = var.subscriber_function_arns
  action        = "lambda:InvokeFunction"
  function_name = each.value
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.topic.arn
}
resource "aws_sns_topic_subscription" "subscriber" {
  for_each  = var.subscriber_function_arns
  topic_arn = aws_sns_topic.topic.arn
  protocol  = "lambda"
  endpoint  = each.value
  # A delivery attempted before the permission exists is refused by Lambda (rules.md D-1).
  depends_on = [aws_lambda_permission.subscriber]
}
