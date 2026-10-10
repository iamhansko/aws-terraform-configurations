# The GameLift server sends each finished game's result here (SendMessageBatch, one message per player), and
# game-sqs-process folds it into the player table.
resource "aws_sqs_queue" "game_result_queue" {
  name                       = var.name
  visibility_timeout_seconds = var.visibility_timeout_seconds
}
