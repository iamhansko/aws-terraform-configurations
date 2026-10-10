# The item image service's vector store: a single-shard MemoryDB cluster with the search module, its subnet
# group, and the security groups on both ends of the Redis connection.
#
# The client group is new. The _monolithic template allowed 6379 from the image service's own security group,
# which would make this module need the service's output while the service needs this one's endpoint. A group
# created here and carried by the tasks says the same thing - "whoever carries this may connect" - without the
# two modules each waiting on the other.
resource "aws_memorydb_subnet_group" "cluster" {
  name        = "${var.name}-subnet-group"
  description = "Subnet group for MemoryDB cluster"
  subnet_ids  = var.subnet_ids
}
resource "aws_security_group" "cluster" {
  name        = "${var.name}-sg"
  description = "Security group for MemoryDB cluster"
  vpc_id      = var.vpc_id
  tags = {
    Name = "${var.name}-sg"
  }
}
resource "aws_security_group" "client" {
  name        = "${var.name}-client-sg"
  description = "Carried by whatever may connect to the ${var.name} MemoryDB cluster"
  vpc_id      = var.vpc_id
  tags = {
    Name = "${var.name}-client-sg"
  }
}
# Standalone rules (rules.md F-2). No egress rule on the cluster group: MemoryDB answers on the connection the
# client opened and starts none of its own.
resource "aws_vpc_security_group_ingress_rule" "redis_from_client" {
  security_group_id            = aws_security_group.cluster.id
  description                  = "Redis from the MemoryDB client security group"
  ip_protocol                  = "tcp"
  from_port                    = var.port
  to_port                      = var.port
  referenced_security_group_id = aws_security_group.client.id
}
# The _monolithic template's second rule, which admitted the whole VPC - the workbench included, which is how
# redis-cli reaches the cluster for inspection.
resource "aws_vpc_security_group_ingress_rule" "redis_from_cidr" {
  for_each          = toset(var.ingress_cidr_blocks)
  security_group_id = aws_security_group.cluster.id
  description       = "Redis from ${each.value}"
  ip_protocol       = "tcp"
  from_port         = var.port
  to_port           = var.port
  cidr_ipv4         = each.value
}
resource "aws_memorydb_cluster" "cluster" {
  name                     = var.name
  node_type                = var.node_type
  engine                   = "redis"
  engine_version           = var.engine_version
  num_shards               = 1
  num_replicas_per_shard   = var.num_replicas_per_shard
  port                     = var.port
  subnet_group_name        = aws_memorydb_subnet_group.cluster.id
  security_group_ids       = [aws_security_group.cluster.id]
  parameter_group_name     = var.parameter_group_name
  acl_name                 = "open-access"
  tls_enabled              = false
  maintenance_window       = var.maintenance_window
  snapshot_retention_limit = var.snapshot_retention_limit
}
