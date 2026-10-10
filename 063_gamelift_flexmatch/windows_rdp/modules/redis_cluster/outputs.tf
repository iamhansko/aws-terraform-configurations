output "address" {
  value       = aws_elasticache_cluster.redis.cache_nodes[0].address
  description = "Host name of the single node, which the functions receive as REDIS"
}
output "port" {
  value       = aws_elasticache_cluster.redis.port
  description = "Port the node listens on"
}
output "cluster_id" {
  value       = aws_elasticache_cluster.redis.cluster_id
  description = "Cluster identifier"
}
