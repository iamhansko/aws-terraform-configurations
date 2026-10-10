# Player records: the password the game client logs in with, the score FlexMatch
# matches on, win and loss counts, and the connection info the match event
# handler writes for the client to poll.
#
# The hash key name is a literal rather than a variable because every handler
# that touches the table addresses items as Key={'PlayerName': ...}; renaming it
# here without rebuilding Lambda/code.zip breaks all four of them.
resource "aws_dynamodb_table" "player_info" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PlayerName"
  attribute {
    name = "PlayerName"
    type = "S"
  }

  # The stream is not decoration. game-rank-update is triggered from it and
  # mirrors every score change into the Redis sorted set the leaderboard reads;
  # Scoring.py reads NewImage and handles REMOVE, so the view type has to carry
  # the new image.
  stream_enabled   = true
  stream_view_type = var.stream_view_type
}
