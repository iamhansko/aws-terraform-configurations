# Every value here is a projection of local.outputs in main.tf. No output in this file carries a value
# expression of its own.
#
# That is what rules.md H-2 requires of a root that declares module "vscode_ec2": the work happens inside
# code-server in a browser, where terraform output does not exist, so the same values are written into a
# README on the instance - and the only way to stop the two copies drifting is for both to read one map. An
# output declared here with its own expression would be missing from that README, and nothing would report it,
# because the apply would succeed either way.
#
# The count is the check: this file has eighteen output blocks and local.outputs has eighteen entries.
#
# The descriptions are the one thing that is restated, because Terraform does not allow an expression in an
# output description - "Error: Variables not allowed" - so they are literals on both sides while the values
# exist only in the map.
output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "The code-server IDE on the workbench. No password - it runs with auth: none, so the address and workbench_ingress_cidr_blocks are the only protection"
}
output "lambda_function_url" {
  value       = local.outputs.lambda_function_url.value
  description = "The HTTP endpoint that turns a POST into an SQS message. Public and unauthenticated while lambda_function_url_authorization_type is NONE"
}
output "lambda_invoke_command" {
  value       = local.outputs.lambda_invoke_command.value
  description = "1. Sends one message by hand, which is the smallest end-to-end test of the whole project"
}
output "queue_depth_command" {
  value       = local.outputs.queue_depth_command.value
  description = "2. Messages waiting and messages in flight. Not a Terraform value and never can be - it changes by the second"
}
output "start_worker_command" {
  value       = local.outputs.start_worker_command.value
  description = "3. Starts the drain on the worker instance. Run it from the workbench over SSH or through SSM Session Manager"
}
output "run_load_generator_command" {
  value       = local.outputs.run_load_generator_command.value
  description = "4. Runs the load generator from the workbench's terminal. Batch counts short of the batch size are Lambda answering 429"
}
output "lambda_throttle_metrics_command" {
  value       = local.outputs.lambda_throttle_metrics_command.value
  description = "5. Invocations, Throttles and Errors for the window. This is the measurement the project exists to produce, and no resource attribute holds it"
}
output "lambda_concurrency_metrics_command" {
  value       = local.outputs.lambda_concurrency_metrics_command.value
  description = "6. Maximum ConcurrentExecutions per minute, which is the ceiling the throttles came from"
}
output "queue_metric_statistics_command" {
  value       = local.outputs.queue_metric_statistics_command.value
  description = "7. The custom metric the log filter publishes - the consumer's count of processed messages"
}
output "queue_log_tail_command" {
  value       = local.outputs.queue_log_tail_command.value
  description = "The raw log lines behind that metric. Lines with no datapoints means the filter pattern, no lines means the worker or the agent"
}
output "worker_status_command" {
  value       = local.outputs.worker_status_command.value
  description = "Whether the worker service is running, and its recent journal"
}
output "worker_log_command" {
  value       = local.outputs.worker_log_command.value
  description = "The worker's log file on the instance, before CloudWatch is involved"
}
output "lambda_logs_command" {
  value       = local.outputs.lambda_logs_command.value
  description = "The function's own log output"
}
output "worker_instance_id" {
  value       = local.outputs.worker_instance_id.value
  description = "ID of the worker instance, for aws ssm start-session"
}
output "worker_private_ip" {
  value       = local.outputs.worker_private_ip.value
  description = "Private address of the worker, reachable from the workbench only"
}
output "private_key_command" {
  value       = local.outputs.private_key_command.value
  description = "Retrieves the generated SSH private key from Parameter Store. A command rather than the key, so this does not print a secret"
}
output "queue_url" {
  value       = local.outputs.queue_url.value
  description = "URL of the queue both the function and the worker are configured against"
}
output "cloud_init_log_command" {
  value       = local.outputs.cloud_init_log_command.value
  description = "The workbench's bootstrap log. First place to look when the IDE does not answer"
}
