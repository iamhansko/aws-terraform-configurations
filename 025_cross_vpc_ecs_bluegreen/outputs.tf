# Every output is a projection of local.outputs in main.tf, which is also what the README on the
# workbench is rendered from (rules.md H-2). No value expression is written here: an output that
# built its own value would be missing from that README, and nothing would fail to tell anyone.
#
# The _monolithic template had no outputs at all - 160 resources and nothing exposed - so
# everything needed to drive the demo had to be found in the console. All of these are new.
#
# description is the one thing repeated, because Terraform rejects an expression there ("Variables
# not allowed") - it has to be a literal.
#
# No output carries a secret. The database password, the credential document and the SSH private
# key appear as the command that fetches them, which keeps them out of state-visible outputs and
# out of a README sitting on an instance whose IDE has authentication disabled.
output "application_urls" {
  value       = local.outputs.application_urls.value
  description = "One URL per application stack, through the public hub network load balancer, the peering connection, the internal app network load balancer and the internal application load balancer"
}
output "error_path_url" {
  value       = local.outputs.error_path_url.value
  description = "URL answered with a fixed 500 by the application load balancer listener, for making the 5xx alarm and the dashboard widget fire"
}
output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "URL of the code-server web UI on the workbench. code-server runs with authentication disabled, so treat this URL as the credential"
}
output "deploy_commands" {
  value       = local.outputs.deploy_commands.value
  description = "One helper script per stack. Running it uploads the pipeline artefact, which starts the pipeline and the CodeDeploy blue/green deployment"
}
output "pipeline_status_commands" {
  value       = local.outputs.pipeline_status_commands.value
  description = "Commands printing each stack's pipeline stages and their last result"
}
output "deployment_status_commands" {
  value       = local.outputs.deployment_status_commands.value
  description = "Commands listing each stack's CodeDeploy deployments, most recent first"
}
output "listener_rules_command" {
  value       = local.outputs.listener_rules_command.value
  description = "Command printing every rule on the application load balancer listener with the target group it forwards to, which is where a blue/green switch is visible"
}
output "hub_target_health_command" {
  value       = local.outputs.hub_target_health_command.value
  description = "Command printing the hub target group's registered targets. These are the app VPC load balancer's private addresses, registered by the workbench bootstrap rather than by Terraform"
}
output "peering_connection" {
  value       = local.outputs.peering_connection.value
  description = "ID of the VPC peering connection with its acceptance state. Anything other than active means nothing crosses between the two VPCs"
}
output "route_tables_command" {
  value       = local.outputs.route_tables_command.value
  description = "Command printing every route table in both VPCs with its routes"
}
output "ecs_cluster_name" {
  value       = local.outputs.ecs_cluster_name.value
  description = "Name of the ECS cluster holding both services"
}
output "container_instances_command" {
  value       = local.outputs.container_instances_command.value
  description = "Command listing the container instances registered with the cluster"
}
output "service_status_command" {
  value       = local.outputs.service_status_command.value
  description = "Command printing both services with their launch type, desired count and running count"
}
output "image_list_command" {
  value       = local.outputs.image_list_command.value
  description = "Commands listing the image tags present in each stack's ECR repository"
}
output "rds_endpoint" {
  value       = local.outputs.rds_endpoint.value
  description = "Aurora writer endpoint with its port and database name. Reachable only from inside the two VPCs"
}
output "rds_secret_command" {
  value       = local.outputs.rds_secret_command.value
  description = "Command fetching the Aurora credential document. The command rather than the password, which must not reach an output or the README on the workbench"
}
output "database_tables_command" {
  value       = local.outputs.database_tables_command.value
  description = "Command listing the tables the schema step created, run from the workbench. Fetches the password from Secrets Manager rather than carrying it"
}
output "rds_instance_status_command" {
  value       = local.outputs.rds_instance_status_command.value
  description = "Command listing the Aurora cluster members and which one is the writer"
}
output "dashboard_url" {
  value       = local.outputs.dashboard_url.value
  description = "Console URL of the CloudWatch dashboard"
}
output "alarm_state_command" {
  value       = local.outputs.alarm_state_command.value
  description = "Command printing both load balancer alarms with their state"
}
output "trail_status_command" {
  value       = local.outputs.trail_status_command.value
  description = "Command showing whether the CloudTrail trail is logging and delivering. The pipeline triggers depend on it entirely"
}
output "private_key_command" {
  value       = local.outputs.private_key_command.value
  description = "Command fetching the generated SSH private key from Parameter Store. The parameter is a SecureString, so only the command is exposed"
}
output "workbench_ssh_command" {
  value       = local.outputs.workbench_ssh_command.value
  description = "SSH command for the workbench, on the port its bootstrap moved sshd to"
}
output "bootstrap_log_command" {
  value       = local.outputs.bootstrap_log_command.value
  description = "Command tailing the workbench user data log, where every bootstrap step is traced"
}
