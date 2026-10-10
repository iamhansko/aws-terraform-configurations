# Player rows: password, score, wins, losses and the ConnectionInfo the match functions hand between each other.
# The stream is what feeds the leaderboard - every score change becomes a record game-rank-update writes into the
# Redis sorted set.
resource "aws_dynamodb_table" "player_table" {
  name         = var.name
  billing_mode = var.billing_mode
  hash_key     = var.hash_key
  attribute {
    name = var.hash_key
    type = "S"
  }
  stream_enabled   = true
  stream_view_type = var.stream_view_type
}
