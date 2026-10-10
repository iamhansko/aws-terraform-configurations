# The role the game server process uses to report results. GomokuServer.exe
# reads ROLE_ARN from its config.ini, calls sts:AssumeRole on it from the fleet
# instance, and with the temporary credentials calls SendMessageBatch on the
# queue in SQS_ENDPOINT (GomokuServer/GameLiftManager.cpp in the sample
# repository). That is the whole of its AWS usage.
#
# Its own module, separate from the fleet, because of when it is needed. The
# userdata writes this ARN into server.zip, so the role has to exist before the
# instance boots - while the fleet has to wait for the instance to have
# uploaded that same server.zip. In one module, the fleet's wait would hold the
# role back with it, and the instance would be waiting on a role that is
# waiting on the instance.
resource "aws_iam_role" "fleet" {
  name_prefix = var.role_name_prefix
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["gamelift.amazonaws.com"]
      }
      Action = ["sts:AssumeRole"]
    }]
  })
}
# What the server actually calls, in place of the _monolithic template's
# AmazonSQSFullAccess (rules.md A-5). SendMessageBatch is authorised as
# sqs:SendMessage, so that one action covers it.
resource "aws_iam_role_policy" "send_game_results" {
  name = "SendGameResults"
  role = aws_iam_role.fleet.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sqs:SendMessage"]
      Resource = var.game_result_queue_arn
    }]
  })
}
# The template's breadth is one variable away: additional_policy_arns =
# ["arn:aws:iam::aws:policy/AmazonSQSFullAccess"] restores it (rules.md B-7).
resource "aws_iam_role_policy_attachment" "additional" {
  for_each   = toset(var.additional_policy_arns)
  role       = aws_iam_role.fleet.name
  policy_arn = each.value
}
