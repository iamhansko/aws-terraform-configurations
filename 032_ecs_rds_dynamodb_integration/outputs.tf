# Every value here is a projection of local.outputs in main.tf, and nothing in this file builds a value of
# its own. That is what makes the workbench README complete: the README renders the same map, so an output
# declared here with its own expression would be an output the README does not contain - and apply would not
# say so (rules.md H-2).
#
# To check the two have not drifted: the number of output blocks in this file must equal the number of
# entries in local.outputs. The keys are known before plan, so
#
#   echo '[for k, v in local.outputs : k]' | terraform console
#
# lists them even while the values are still unknown.
#
# description is the one thing that cannot be read from the map. Terraform does not allow an expression
# there - "Variables may not be used here" - so the wording is a literal in both places. The values are
# still defined once.
output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "The workbench. Every command below is meant to be run from its terminal, and the three services have no other way in - their tasks have private addresses only"
}
output "image_build_order" {
  value       = local.outputs.image_build_order.value
  description = "The order the three images are built in, one after another on the workbench instance"
}
output "image_build_status_command" {
  value       = local.outputs.image_build_status_command.value
  description = "The status of each image build step - the work the _monolithic template's cfn-init calls never performed"
}
output "image_build_output_command" {
  value       = local.outputs.image_build_output_command.value
  description = "The first build step's stdout and stderr, where a build failure says what went wrong"
}
output "ecr_list_images_command" {
  value       = local.outputs.ecr_list_images_command.value
  description = "One image listing per repository. An empty table is the first thing to check when a service reports CannotPullContainerError"
}
output "service_status_command" {
  value       = local.outputs.service_status_command.value
  description = "Desired against running task counts for each of the three services"
}
output "service_events_command" {
  value       = local.outputs.service_events_command.value
  description = "Each service's own account of what it has been trying to do, where nearly every failure appears first"
}
output "stopped_task_reason_command" {
  value       = local.outputs.stopped_task_reason_command.value
  description = "Why stopped tasks stopped, per service"
}
output "service_health_command" {
  value       = local.outputs.service_health_command.value
  description = "Resolves each service's first running task and requests its health endpoint - the build, push, pull, start and network path in three lines"
}
output "user_write_command" {
  value       = local.outputs.user_write_command.value
  description = "Writes a row through the user service, which is the request that needs the MySQL table the schema step creates"
}
output "user_read_command" {
  value       = local.outputs.user_read_command.value
  description = "Reads that row back through the user service"
}
output "product_write_command" {
  value       = local.outputs.product_write_command.value
  description = "Writes an item through the product service. It used to return 500 from an aws-sdk-go-v2 version mismatch in src/product/go.mod; writing the same id again replaces the item"
}
output "product_read_command" {
  value       = local.outputs.product_read_command.value
  description = "Reads it back by id. It used to return 500 because the _monolithic table had a composite id + price key and this GetItem names id alone; the table is keyed on id alone now"
}
output "dynamodb_scan_command" {
  value       = local.outputs.dynamodb_scan_command.value
  description = "The item as DynamoDB holds it rather than as the service renders it"
}
output "stress_command" {
  value       = local.outputs.stress_command.value
  description = "Asks the stress service for random data. It touches no AWS service, which is why its task role needs nothing"
}
output "container_log_command" {
  value       = local.outputs.container_log_command.value
  description = "Container output per service. An addition: the template configured no log driver at all"
}
output "mysql_session_command" {
  value       = local.outputs.mysql_session_command.value
  description = "An interactive MySQL session from the workbench, with the password fetched inline"
}
output "rds_credentials_command" {
  value       = local.outputs.rds_credentials_command.value
  description = "Retrieves the generated database credential from Secrets Manager. A command rather than the password, because this map is also written to a file an unauthenticated code-server serves"
}
output "rds_storage_command" {
  value       = local.outputs.rds_storage_command.value
  description = "The storage figures as RDS holds them, next to the instance class driving them"
}
output "rds_replica_status_command" {
  value       = local.outputs.rds_replica_status_command.value
  description = "Whether the second instance is really a read replica, which is what the conversion lost when it could not map SourceDBInstanceIdentifier"
}
output "cluster_status_command" {
  value       = local.outputs.cluster_status_command.value
  description = "Registered container instances and running against pending task counts"
}
output "container_instance_status_command" {
  value       = local.outputs.container_instance_status_command.value
  description = "Which instances registered and how much memory each has left"
}
output "task_role_policy_command" {
  value       = local.outputs.task_role_policy_command.value
  description = "What the ECS task role can do. The point is what is not there: the template gave it AdministratorAccess"
}
output "ecs_exec_command" {
  value       = local.outputs.ecs_exec_command.value
  description = "A shell inside the first running task of each service, through ECS Exec"
}
output "rds_endpoint" {
  value       = local.outputs.rds_endpoint.value
  description = "Host and port of the primary database instance"
}
output "rds_replica_address" {
  value       = local.outputs.rds_replica_address.value
  description = "Hostname of the read replica, which nothing in this project connects to"
}
output "dynamodb_table_name" {
  value       = local.outputs.dynamodb_table_name.value
  description = "Name of the table the product service writes to"
}
output "ecs_cluster_name" {
  value       = local.outputs.ecs_cluster_name.value
  description = "Name of the ECS cluster"
}
output "capacity_provider_name" {
  value       = local.outputs.capacity_provider_name.value
  description = "The capacity provider the three services place tasks through"
}
output "ecr_repository_urls" {
  value       = local.outputs.ecr_repository_urls.value
  description = "The image references the builds push and the task definitions pull"
}
output "docker_login_command" {
  value       = local.outputs.docker_login_command.value
  description = "The ECR login the build steps run, for repeating a push by hand"
}
output "vpc_id" {
  value       = local.outputs.vpc_id.value
  description = "ID of the VPC"
}
output "nat_gateway_public_ips" {
  value       = local.outputs.nat_gateway_public_ips.value
  description = "What the container instances and task ENIs appear as from outside"
}
output "cloud_init_log_command" {
  value       = local.outputs.cloud_init_log_command.value
  description = "The workbench's bootstrap log, which is where to look when code-server did not come up"
}
output "private_key_command" {
  value       = local.outputs.private_key_command.value
  description = "Retrieves the generated SSH private key from Parameter Store. A command rather than the key"
}
