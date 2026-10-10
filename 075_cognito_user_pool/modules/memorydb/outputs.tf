output "endpoint_address" {
  value       = aws_memorydb_cluster.cluster.cluster_endpoint[0].address
  description = "Cluster endpoint host, which the item image service takes as REDIS_HOST"
}
output "port" {
  value       = aws_memorydb_cluster.cluster.cluster_endpoint[0].port
  description = "Cluster endpoint port"
}
output "client_security_group_id" {
  value       = aws_security_group.client.id
  description = "Security group that admits its carrier to the cluster. Attach it to the tasks that connect"
}
output "ping_command" {
  value       = "redis6-cli -h ${aws_memorydb_cluster.cluster.cluster_endpoint[0].address} -p ${aws_memorydb_cluster.cluster.cluster_endpoint[0].port} PING"
  description = "Checks the cluster answers. From the workbench, which is in the VPC CIDR the cluster admits. Amazon Linux 2023 packages the client as redis6, and names its binary redis6-cli rather than redis-cli"
}
