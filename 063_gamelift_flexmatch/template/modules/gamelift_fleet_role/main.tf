# The role the game server process works as. Its own module, separate from the fleet, because its ARN is baked
# into server.zip: the workbench writes it into the server's config.ini as ROLE_ARN before zipping the build, so
# it has to exist before the instance boots - while the fleet has to wait until the upload is done. Inside the
# fleet module, the fleet's wait on the upload would have held this role back too, and the instance waiting on
# the role would have closed a cycle.
#
# The server calls sts:AssumeRole on this ARN (GameLiftManager.cpp, GetAWSCredentials) and uses the result for
# exactly one call, SQS SendMessageBatch to the game result queue - authorized as sqs:SendMessage. That is the
# whole grant. The _monolithic template attached AmazonSQSFullAccess, which also covers creating, purging and
# deleting every queue in the account (rules.md A-5).
resource "aws_iam_role" "fleet_role" {
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
resource "aws_iam_role_policy" "send_game_results" {
  name = "SendGameResults"
  role = aws_iam_role.fleet_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "SendGameResults"
      Effect   = "Allow"
      Action   = ["sqs:SendMessage"]
      Resource = [var.game_result_queue_arn]
    }]
  })
}
resource "aws_iam_role_policy_attachment" "additional" {
  for_each   = toset(var.additional_policy_arns)
  role       = aws_iam_role.fleet_role.name
  policy_arn = each.value
}
