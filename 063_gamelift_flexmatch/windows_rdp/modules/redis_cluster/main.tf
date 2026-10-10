# The leaderboard store: one Redis node holding a single sorted set, Rating,
# which game-rank-update writes from the DynamoDB stream and game-rank-reader
# returns to the web page.
#
# Private subnets only, where the _monolithic template listed all four.
# The public pair added nothing: ElastiCache never gives a node a public
# address, so a node placed in a public subnet is reachable from exactly the
# same places as one in a private subnet - members of GomokuDefault inside this
# VPC. The template's own 05ElasticacheRedisConnect output already assumed that
# ("Use CloudShell in the VPC"). The same list was copied onto the two
# VPC-attached functions, where public subnets are an actual trap rather than
# noise - a Lambda ENI has no public address, so a function placed there has no
# route out - and the root gives them the private pair too.
resource "aws_elasticache_subnet_group" "redis" {
  name        = var.subnet_group_name
  description = "Subnet Group"
  subnet_ids  = var.subnet_ids
}
resource "aws_elasticache_cluster" "redis" {
  cluster_id         = var.cluster_id
  engine             = "redis"
  engine_version     = var.engine_version
  node_type          = var.node_type
  num_cache_nodes    = 1
  port               = var.port
  subnet_group_name  = aws_elasticache_subnet_group.redis.name
  security_group_ids = var.security_group_ids
}
