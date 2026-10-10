# The leaderboard's sorted set ("Rating"), written by game-rank-update from the player table's stream and read by
# game-rank-reader for the API.
resource "aws_elasticache_subnet_group" "ranking_cache_subnet_group" {
  name        = var.subnet_group_name
  description = "Subnet Group"
  subnet_ids  = var.subnet_ids
}
resource "aws_elasticache_cluster" "ranking_cache" {
  cluster_id         = var.cluster_id
  engine             = "redis"
  engine_version     = var.engine_version
  node_type          = var.node_type
  num_cache_nodes    = 1
  port               = var.port
  subnet_group_name  = aws_elasticache_subnet_group.ranking_cache_subnet_group.name
  security_group_ids = var.security_group_ids
}
