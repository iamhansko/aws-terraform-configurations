# Every value here is a projection of local.outputs in main.tf, which the README written onto the workbench
# renders from the same map - so no value expression exists twice, and an output cannot be added without also
# appearing in that README (rules.md B-5/H-2).
#
# description is the one thing that cannot be projected: Terraform rejects an expression in an output's
# description ("Variables not allowed"), so the wording is a literal on both sides.
output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "The workbench. Every command below is meant to be run from its terminal"
}
output "alb_url" {
  value       = local.outputs.alb_url.value
  description = "Each request is one access log line from the container, which is the record this project streams"
}
output "generate_traffic_command" {
  value       = local.outputs.generate_traffic_command.value
  description = "Fifty requests, one status code per line. 200s mean the ALB, the target group and the tasks are all reachable"
}
output "tail_logs_command" {
  value       = local.outputs.tail_logs_command.value
  description = "The stream half: CloudWatch receives each line as nginx writes it, and the subscription hands it to Firehose the moment it arrives"
}
output "list_delivered_command" {
  value       = local.outputs.list_delivered_command.value
  description = "The batch half: Firehose holds what it receives and writes one object per buffering interval (firehose_buffering_interval_seconds, 300 by default) or 5 MB, whichever comes first. Empty until the first interval has passed"
}
output "read_delivered_command" {
  value       = local.outputs.read_delivered_command.value
  description = "Gunzipped twice, because CloudWatch Logs already gzips what it sends to a subscription and the stream's GZIP compresses it again. What comes out is CloudWatch's JSON envelope with the nginx lines inside logEvents"
}
output "list_errors_command" {
  value       = local.outputs.list_errors_command.value
  description = "Should stay empty. Anything here is the reason a gap appears under the delivered prefix"
}
output "describe_delivery_stream_command" {
  value       = local.outputs.describe_delivery_stream_command.value
  description = "ENABLED with CUSTOMER_MANAGED_CMK is the encryption the _monolithic template declared a key for and then lost in conversion"
}
output "service_status_command" {
  value       = local.outputs.service_status_command.value
  description = "Desired against running tasks and the rollout state"
}
output "service_events_command" {
  value       = local.outputs.service_events_command.value
  description = "Where a pull failure, an unhealthy target or a circuit-breaker rollback is reported first"
}
output "target_health_command" {
  value       = local.outputs.target_health_command.value
  description = "Whether the ALB can reach the tasks. Target.Timeout is a security group path problem rather than an application one"
}
output "execute_command" {
  value       = local.outputs.execute_command.value
  description = "ECS Exec. The session itself is logged to the same group, so it streams to S3 along with the access log"
}
output "ecs_cluster_name" {
  value       = local.outputs.ecs_cluster_name.value
  description = "Name of the ECS cluster"
}
output "ecs_service_name" {
  value       = local.outputs.ecs_service_name.value
  description = "Name of the ECS service"
}
output "log_group_name" {
  value       = local.outputs.log_group_name.value
  description = "The group the containers write to and Firehose is subscribed to"
}
output "delivery_stream_name" {
  value       = local.outputs.delivery_stream_name.value
  description = "Name of the Firehose delivery stream"
}
output "destination_bucket_name" {
  value       = local.outputs.destination_bucket_name.value
  description = "Where Firehose writes. terraform destroy empties it first, so the delivered logs go with it"
}
output "private_key_command" {
  value       = local.outputs.private_key_command.value
  description = "Retrieves the generated private key from Parameter Store. No security group opens port 22; this is for the case where the SSM agent is what is broken"
}
