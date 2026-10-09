# Every value here is a projection of local.outputs in main.tf, which the README written onto the workbench
# renders from the same map - so no value expression exists twice, and an output cannot be added without
# also appearing in that README (rules.md B-5/H-2).
#
# The _monolithic template had no outputs at all, which for a project whose whole subject is observing a
# running service meant nothing it produced was addressable from the configuration.
#
# description is the one thing that cannot be projected: Terraform rejects an expression in an output's
# description ("Variables not allowed"), so the wording is a literal on both sides.
output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "The workbench. Every command below is meant to be run from its terminal, and code-server runs without authentication - so this URL is the credential"
}
output "alb_url" {
  value       = local.outputs.alb_url.value
  description = "The Flask app from src/monitoring.py, answering on / with Hello ECS"
}
output "hello_command" {
  value       = local.outputs.hello_command.value
  description = "Ten requests, one status code per line. 200s mean the ALB, the target group, the task and the image are all in place"
}
output "error_command" {
  value       = local.outputs.error_command.value
  description = "The /error route returns 500 on purpose. alarm_threshold is 2 within one alarm_period of 300 seconds, so five is comfortably over it"
}
output "alarm_state_command" {
  value       = local.outputs.alarm_state_command.value
  description = "OK before the step above and ALARM a few minutes after it. The _monolithic template's alarm had an empty dimension map, so it stayed in INSUFFICIENT_DATA whatever the load balancer returned - this is the command that shows the difference"
}
output "dashboard_url" {
  value       = local.outputs.dashboard_url.value
  description = "ECS CPU and memory on the left, ALB request count and 5xx on the right. The 5xx series fills in from the step above"
}
output "service_status_command" {
  value       = local.outputs.service_status_command.value
  description = "Desired against running task counts and the rollout state"
}
output "service_events_command" {
  value       = local.outputs.service_events_command.value
  description = "The service's own account of what it has been doing. A pull failure or an unhealthy target is reported here before anywhere else"
}
output "target_health_command" {
  value       = local.outputs.target_health_command.value
  description = "Whether the load balancer can reach the task. Target.Timeout here is a security group path problem rather than an application one, and it is what the _monolithic template's missing egress rules produced"
}
output "tail_logs_command" {
  value       = local.outputs.tail_logs_command.value
  description = "Flask logs one line per request. An addition to the original, whose container definition had no log configuration at all - so on Fargate, with no instance to run docker logs on, a task that failed to start said nothing anywhere"
}
output "list_images_command" {
  value       = local.outputs.list_images_command.value
  description = "One image, pushed by this instance during its bootstrap. An empty table means the build never got as far as pushing, and the reason is in /var/log/cloud-init-output.log on this box"
}
output "rebuild_command" {
  value       = local.outputs.rebuild_command.value
  description = "Edit /home/ec2-user/image/monitoring.py, then run this. The task definition names a moving tag, so the push alone changes nothing until the tasks are replaced - which is what the second command does. Keep src/monitoring.py in this repository in step, because the next apply ships that file and not the edited one"
}
output "ecs_cluster_name" {
  value       = local.outputs.ecs_cluster_name.value
  description = "Name of the ECS cluster"
}
output "ecs_service_name" {
  value       = local.outputs.ecs_service_name.value
  description = "Name of the ECS service"
}
output "ecr_repository_url" {
  value       = local.outputs.ecr_repository_url.value
  description = "Host and path the workbench pushes to and the task definition pulls from"
}
output "log_group_name" {
  value       = local.outputs.log_group_name.value
  description = "Where the container's stdout goes"
}
output "dashboard_name" {
  value       = local.outputs.dashboard_name.value
  description = "Name of the CloudWatch dashboard"
}
output "alarm_name" {
  value       = local.outputs.alarm_name.value
  description = "Name of the 5xx alarm"
}
output "alarm_actions_enabled" {
  value       = local.outputs.alarm_actions_enabled.value
  description = "Whether the alarm has anywhere to notify. False unless the alarm_actions variable was given a topic ARN - the _monolithic template set actions_enabled = true with no actions, which reads as configured notification and delivers nothing"
}
output "private_key_command" {
  value       = local.outputs.private_key_command.value
  description = "Retrieves the generated private key from Parameter Store into key.pem. CloudFormation puts a key pair it generates there, and this reproduces that"
}
output "ssh_command" {
  value       = local.outputs.ssh_command.value
  description = "For the case where code-server is what is broken. Run the command above first to get key.pem"
}
