# Every value here is a projection of local.outputs in main.tf, which the README written onto the
# workbench renders from the same map - so no value expression exists twice, and an output cannot be added
# without also appearing in that README (rules.md B-5/H-2).
#
# description is the one thing that cannot be projected: Terraform rejects an expression in an output's
# description ("Variables not allowed"), so the wording is a literal on both sides.
#
# Twenty-one entries where the _monolithic template had one. That template exposed the code-server URL and
# nothing else, which meant a person inside that IDE - the only place this project is meant to be worked
# from - could not see the cluster, the log group, or any way to check whether a record had arrived.
output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "The workbench. Every numbered command below is meant to be run from its terminal, and the AWS CLI there is already pointed at this region"
}
output "ecs_cluster_name" {
  value       = local.outputs.ecs_cluster_name.value
  description = "Name of the cluster running the logging task"
}
output "ecs_service_name" {
  value       = local.outputs.ecs_service_name.value
  description = "Name of the service. It has no load balancer and publishes no port, which is correct: the application is a loop that prints a JSON line and sleeps, so there is nothing to serve and nothing to health-check"
}
output "application_log_group_name" {
  value       = local.outputs.application_log_group_name.value
  description = "The log group the application's lines end up in. The path is: the container prints JSON to stdout, the fluentd log driver hands each line to the Fluent Bit sidecar over a Unix socket in the task, and Fluent Bit's cloudwatch_logs output plugin calls PutLogEvents against this group. Terraform creates the group, so it has a retention and it goes away with terraform destroy - the _monolithic template let Fluent Bit create it at runtime instead, which left it behind after every teardown"
}
output "log_router_log_group_name" {
  value       = local.outputs.log_router_log_group_name.value
  description = "Fluent Bit cannot report its own failures through itself, so its stdout goes to this group by the ordinary awslogs driver. When the group above is empty, this one holds the reason"
}
output "tail_application_logs_command" {
  value       = local.outputs.tail_application_logs_command.value
  description = "The result of the project, live. One line per record Fluent Bit delivered, from two tasks at once. Silence here while the service reports two running tasks means the pipeline rather than the application, and the next thing to read is step 4"
}
output "read_one_record_command" {
  value       = local.outputs.read_one_record_command.value
  description = "What arrives is not the application's JSON but FireLens's envelope around it: container_id, container_name, source, ecs_cluster, ecs_task_arn, ecs_task_definition and ec2_instance_id, with the application's own line as a string in the \"log\" field. Seeing that envelope is how you know the record came through the log router rather than the awslogs driver"
}
output "find_error_records_command" {
  value       = local.outputs.find_error_records_command.value
  description = "The application adds a random \"token\" field to its ERROR lines and to no others. This is the demo's argument for a log router: a field you would want redacted, or sent somewhere other than CloudWatch, is visible here - and changing where it goes is an options change in the task definition rather than an application change"
}
output "tail_log_router_logs_command" {
  value       = local.outputs.tail_log_router_logs_command.value
  description = "Fluent Bit's version banner, the output plugin it loaded, the destination it resolved, and any delivery error. An AccessDeniedException or a missing-group error from CloudWatch Logs appears here and nowhere else - ECS reports the task as healthy throughout. This group is only useful because FLB_LOG_LEVEL is info; at the error level the _monolithic template set, a working pipeline writes nothing here and so looks exactly like a broken one"
}
output "describe_task_definition_command" {
  value       = local.outputs.describe_task_definition_command.value
  description = "The registered log configuration for both containers, as ECS stored it. This is the authoritative answer to \"where are the logs going\": these options are exactly what the agent turns into the Fluent Bit configuration file, and a misspelled option name is accepted silently by plan, by apply and by the service"
}
output "service_status_command" {
  value       = local.outputs.service_status_command.value
  description = "Desired against running counts and the rollout state"
}
output "service_events_command" {
  value       = local.outputs.service_events_command.value
  description = "The service's own account of what it has been trying to do. Most failures here land in this list rather than anywhere in Terraform"
}
output "stopped_task_reason_command" {
  value       = local.outputs.stopped_task_reason_command.value
  description = "Per container, which matters because both are essential - either one stopping takes the task with it. CannotPullContainerError means the build never pushed; a logging driver failure on the log router means its log group or the permission for it"
}
output "running_task_placement_command" {
  value       = local.outputs.running_task_placement_command.value
  description = "Two task ARNs is what makes step 2 interesting: each task has its own Fluent Bit sidecar and its own log stream, so the per-task metadata in the records differs between them"
}
output "container_instances_command" {
  value       = local.outputs.container_instances_command.value
  description = "An empty list alongside a healthy Auto Scaling group is the signature of instances with no outbound path or without the container instance role - and because an instance that never registers never becomes an ECS object, nothing reports it as an error"
}
output "container_instance_session_command" {
  value       = local.outputs.container_instance_session_command.value
  description = "Two things are worth looking at from there: /var/log/ecs/ecs-agent.log for why an instance did not register, and /var/lib/ecs/data/firelens/<task-id>/config, which is the Fluent Bit configuration file the agent generated from the task definition's log options"
}
output "application_image_uri" {
  value       = local.outputs.application_image_uri.value
  description = "Built on the workbench from a four-line Dockerfile around the log generator, and pushed here. The CMD runs python with -u: without it stdout is block-buffered into an 8 KB pipe, so roughly eighty lines pile up before any of them is written and the stream arrives in bursts a minute and a half apart - which for a logging demo is indistinguishable from a broken pipeline"
}
output "log_router_image_uri" {
  value       = local.outputs.log_router_image_uri.value
  description = "AWS's published aws-for-fluent-bit image, pulled and re-pushed into a private repository under this tag. The Dockerfile is a single FROM line and nothing else - no configuration is baked in, because FireLens generates the configuration file and mounts it over /fluent-bit/etc/fluent-bit.conf at task start, which is what makes a bare re-tag work"
}
output "list_application_images_command" {
  value       = local.outputs.list_application_images_command.value
  description = "An empty table means the build never got as far as pushing, and the reason is in the image-build association's output rather than anywhere in ECS"
}
output "list_fluentbit_images_command" {
  value       = local.outputs.list_fluentbit_images_command.value
  description = "Same check for the other half. The sizes differ by roughly an order of magnitude, which is the quickest way to tell at a glance that the two Dockerfiles did not get swapped"
}
output "private_key_command" {
  value       = local.outputs.private_key_command.value
  description = "Retrieves the generated private key from Parameter Store. SSH is open on the workbench by default, but this is mostly for the case where the SSM agent is what is broken - in which case none of the associations ran either"
}
