# Where the game server reports each finished game: GomokuServer.exe calls
# SendMessageBatch with one message per player (score, win and loss deltas), and
# game-sqs-process applies them to the player table. The server finds the queue
# through SQS_ENDPOINT in the config.ini the userdata bakes into server.zip, so
# the URL is what matters and the name is free.
resource "aws_sqs_queue" "game_result" {
  name = var.queue_name

  # Lambda refuses an SQS event source mapping whose queue visibility timeout is
  # shorter than the function timeout; the root validates the pair.
  visibility_timeout_seconds = var.visibility_timeout_seconds
}
