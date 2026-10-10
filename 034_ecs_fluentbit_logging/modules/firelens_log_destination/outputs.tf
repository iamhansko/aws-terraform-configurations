output "application_log_group_name" {
  value       = aws_cloudwatch_log_group.application_logs.name
  description = "Log group the application's lines arrive in"
}
output "application_log_group_arn" {
  value       = aws_cloudwatch_log_group.application_logs.arn
  description = "ARN of the application log group"
}
output "log_router_log_group_name" {
  value       = aws_cloudwatch_log_group.log_router_logs.name
  description = "Log group the log router's own stdout arrives in"
}
output "log_router_log_group_arn" {
  value       = aws_cloudwatch_log_group.log_router_logs.arn
  description = "ARN of the log router log group"
}
output "log_router_policy_arn" {
  value       = aws_iam_policy.log_router.arn
  description = "ARN of the policy that lets the log router write to the application log group. Attached to the task role rather than the execution role, because the task role is the one the Fluent Bit process itself assumes"
}
# The two logConfiguration option maps, assembled here rather than in the task definition.
#
# The destination name appears in three places in this project: the FireLens options the task definition
# carries, the IAM policy above, and the verification command in the README. Handing the whole options map
# back out is what keeps those three reading one value (rules.md B-5) - a task definition that names a
# group this module did not create produces no error at apply, no error in the service, and no log lines.
output "application_firelens_options" {
  value = {
    Name              = "cloudwatch_logs"
    region            = data.aws_region.current.region
    log_group_name    = aws_cloudwatch_log_group.application_logs.name
    log_stream_prefix = var.log_stream_prefix
    # A string rather than a bool: these options are rendered into a Fluent Bit configuration file, and
    # the ECS API takes logConfiguration options as a map of strings.
    auto_create_group = tostring(var.auto_create_group)
  }
  description = "Options for the application container's awsfirelens log configuration. Name selects the Fluent Bit output plugin; everything else is passed through into the generated [OUTPUT] section"
}
output "log_router_awslogs_options" {
  value = {
    "awslogs-group"  = aws_cloudwatch_log_group.log_router_logs.name
    "awslogs-region" = data.aws_region.current.region
  }
  description = "Options for the log router container's own awslogs log configuration. awslogs-create-group is deliberately absent - the group above exists, so neither the task execution role nor the container instance role needs logs:CreateLogGroup, and both already carry CreateLogStream and PutLogEvents through their standard managed policies"
}
output "auto_create_group" {
  value       = var.auto_create_group
  description = "Whether the plugin was told to create the application group itself, handed back out so the root can report which of the two shapes is in effect (rules.md B-5)"
}
# Terraform cannot know whether a log line arrived - that happens after apply returns - so the checks are
# commands. For a logging project these are the result rather than a convenience.
output "tail_application_logs_command" {
  value       = "aws logs tail ${aws_cloudwatch_log_group.application_logs.name} --follow --since 5m"
  description = "The whole point of the project, live. Each line is one record Fluent Bit delivered. Silence here with a healthy service means the pipeline is broken rather than the application, and the next command to run is the log router one"
}
output "read_one_record_command" {
  value       = "aws logs filter-log-events --log-group-name ${aws_cloudwatch_log_group.application_logs.name} --limit 1 --query 'events[0].message' --output text | python3 -m json.tool"
  description = "One delivered record, formatted. What comes back is not the application's JSON but FireLens's envelope around it - container_id, container_name, source, ecs_cluster, ecs_task_arn, ecs_task_definition, ec2_instance_id - with the application's own line as a string in the \"log\" field. Confirming that envelope is how you know the record went through the log router rather than the awslogs driver"
}
output "find_error_records_command" {
  value       = "aws logs filter-log-events --log-group-name ${aws_cloudwatch_log_group.application_logs.name} --filter-pattern '\"ERROR\"' --limit 5 --query 'events[].message' --output text"
  description = "The ERROR records, which are the only ones the application adds a \"token\" field to. This is the demo's argument for a log router: a field you would want redacted or routed somewhere other than CloudWatch is visible here, and changing where it goes is an options change in the task definition rather than an application change"
}
output "tail_log_router_logs_command" {
  value       = "aws logs tail ${aws_cloudwatch_log_group.log_router_logs.name} --follow --since 10m"
  description = "Fluent Bit's own output. The startup banner naming the version, the [OUTPUT] plugin it loaded, and any delivery error. An AccessDeniedException or a ResourceNotFoundException for the application group shows up here and nowhere else - ECS reports the task as healthy throughout"
}
