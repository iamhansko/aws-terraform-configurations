output "address" {
  value       = aws_elasticache_cluster.ranking_cache.cache_nodes[0].address
  description = "DNS name of the single Redis node, which both ranking functions read from their REDIS environment variable"
}
output "port" {
  value       = aws_elasticache_cluster.ranking_cache.port
  description = "Port the node listens on, re-exposed so the README command and the security group rule use the value the node was created with (rules.md B-5)"
}
