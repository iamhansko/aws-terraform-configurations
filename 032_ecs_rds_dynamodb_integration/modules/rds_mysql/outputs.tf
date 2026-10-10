output "identifier" {
  value       = aws_db_instance.rds_instance_primary.identifier
  description = "Identifier of the primary instance"
}
output "address" {
  value       = aws_db_instance.rds_instance_primary.address
  description = "Hostname of the primary. This is what the user task definition receives as MYSQL_HOST, and the same value is inside the credential secret - both read from here (rules.md B-5)"
}
output "port" {
  value       = aws_db_instance.rds_instance_primary.port
  description = "Port the primary listens on, read off the instance rather than from the variable so it is the port RDS actually opened"
}
output "endpoint" {
  value       = aws_db_instance.rds_instance_primary.endpoint
  description = "Host and port together, as RDS reports it"
}
output "db_name" {
  value       = aws_db_instance.rds_instance_primary.db_name
  description = "Initial database. The schema step creates its table here and the user application connects to it"
}
output "username" {
  value       = var.username
  description = "Master username, handed back out so the caller's environment wiring and its schema step read one value (rules.md B-5)"
}
output "multi_az" {
  value       = aws_db_instance.rds_instance_primary.multi_az
  description = "Whether the primary has a synchronous standby. Separate from the read replica below, and both being true is intentional - see main.tf"
}
output "replica_identifier" {
  value       = var.create_read_replica ? aws_db_instance.rds_instance_replica[0].identifier : null
  description = "Identifier of the read replica, or null when create_read_replica is false"
}
output "replica_address" {
  value       = var.create_read_replica ? aws_db_instance.rds_instance_replica[0].address : null
  description = "Hostname of the read replica, or null. Nothing in this project connects to it - the user task definition only gets the primary - so this is the only way to reach it"
}
output "security_group_id" {
  value       = aws_security_group.rds_security_group.id
  description = "ID of the database security group, so a caller can name it as a source elsewhere"
}
output "credentials_secret_arn" {
  value       = aws_secretsmanager_secret.credentials.arn
  description = "ARN of the credential secret. The task definition's secrets list selects the password key out of this, and the task execution role's policy names exactly this ARN rather than \"*\" (rules.md A-5)"
}
output "credentials_secret_name" {
  value       = aws_secretsmanager_secret.credentials.name
  description = "Generated name of the credential secret"
}
output "password_secret_reference" {
  value       = "${aws_secretsmanager_secret.credentials.arn}:password::"
  description = "The valueFrom a task definition uses to inject only the password out of the JSON document. Assembled here rather than in the caller, so the key name and the ARN travel together (rules.md B-5)"
}
output "get_credentials_command" {
  value       = "aws secretsmanager get-secret-value --secret-id ${aws_secretsmanager_secret.credentials.arn} --query SecretString --output text"
  description = "Retrieves the credential document. A command rather than the password itself, because every output here is also written to the workbench README on disk (rules.md H-2)"
}
output "mysql_connect_command" {
  value       = "mysql -h ${aws_db_instance.rds_instance_primary.address} -P ${aws_db_instance.rds_instance_primary.port} -u ${var.username} -p\"$(aws secretsmanager get-secret-value --secret-id ${aws_secretsmanager_secret.credentials.arn} --query SecretString --output text | python -c 'import json,sys; print(json.load(sys.stdin)[\"password\"])')\" ${aws_db_instance.rds_instance_primary.db_name}"
  description = "An interactive MySQL session from the workbench, with the password fetched inline so it is never typed or stored in shell history. Only the workbench can reach the database - the instance is in private subnets and its security group names that one group as a source"
}
output "describe_command" {
  value       = "aws rds describe-db-instances --db-instance-identifier ${aws_db_instance.rds_instance_primary.identifier} --query 'DBInstances[0].[DBInstanceStatus,MultiAZ,StorageType,AllocatedStorage,Iops,StorageThroughput,DBInstanceClass]' --output json"
  description = "The storage figures as RDS holds them, next to the instance class driving them. Worth comparing: 12000 IOPS and 500 MiB/s on a db.t3.micro is performance the class cannot deliver - see the instance_class variable"
}
output "replica_status_command" {
  value       = var.create_read_replica ? "aws rds describe-db-instances --db-instance-identifier ${aws_db_instance.rds_instance_replica[0].identifier} --query 'DBInstances[0].[DBInstanceStatus,ReadReplicaSourceDBInstanceIdentifier,StatusInfos]' --output json" : null
  description = "Whether this really is a replica, and of what. ReadReplicaSourceDBInstanceIdentifier being populated is the difference between a replica and the standalone second instance the conversion left behind - see main.tf"
}
