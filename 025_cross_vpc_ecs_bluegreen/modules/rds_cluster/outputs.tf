output "cluster_endpoint" {
  value       = aws_rds_cluster.rds_cluster.endpoint
  description = "Writer endpoint of the cluster. Resolves as soon as the cluster exists and answers nothing until an instance is attached, which is what the _monolithic template's aws_db_instance conversion left behind"
}
output "reader_endpoint" {
  value       = aws_rds_cluster.rds_cluster.reader_endpoint
  description = "Reader endpoint, load balancing across the non-writer instances"
}
output "port" {
  value       = aws_rds_cluster.rds_cluster.port
  description = "Port the cluster listens on, re-exposed so a caller building a connection command does not restate it (rules.md B-5)"
}
output "database_name" {
  value       = aws_rds_cluster.rds_cluster.database_name
  description = "Initial database name"
}
output "master_username" {
  value       = aws_rds_cluster.rds_cluster.master_username
  description = "Master user name. The user is not the secret; the password is, and it is not exposed here"
}
output "secret_arn" {
  value       = aws_secretsmanager_secret.rds_secret.arn
  description = "ARN of the credential secret. Each task definition appends a key and a version suffix to it - <arn>:DB_URL:: - and the ECS task execution role policy is scoped to this one ARN (rules.md A-5)"
}
output "secret_name" {
  value       = aws_secretsmanager_secret.rds_secret.name
  description = "Name of the credential secret"
}
output "secret_command" {
  value       = "aws secretsmanager get-secret-value --secret-id ${aws_secretsmanager_secret.rds_secret.name} --query SecretString --output text"
  description = "Command that fetches the credential document. The retrieval command rather than the password, which must not reach an output or the README on the workbench (rules.md H-2)"
}
output "security_group_id" {
  value       = aws_security_group.rds_security_group.id
  description = "The database security group"
}
output "instance_identifiers" {
  value       = [for instance in aws_rds_cluster_instance.rds_cluster_instance : instance.identifier]
  description = "Identifiers of the cluster instances"
}
output "instance_status_command" {
  value       = "aws rds describe-db-clusters --db-cluster-identifier ${aws_rds_cluster.rds_cluster.id} --query 'DBClusters[0].DBClusterMembers[].[DBInstanceIdentifier,IsClusterWriter,DBClusterParameterGroupStatus]' --output table"
  description = "Command listing the cluster members and which one is the writer. An empty list is the shape of the bug the original had: a cluster with no instances"
}
