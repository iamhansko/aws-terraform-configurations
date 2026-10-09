output "task_role_arn" {
  value       = aws_iam_role.ecs_task_role.arn
  description = "ARN of the task role, named by every task definition. Used at runtime by the FireLens sidecar and by nothing else in this project"
}
output "task_role_name" {
  value       = aws_iam_role.ecs_task_role.name
  description = "Generated name of the task role"
}
output "execution_role_arn" {
  value       = aws_iam_role.ecs_task_execution_role.arn
  description = "ARN of the task execution role, named by every task definition. Used by the ECS agent before a container starts: the ECR pull, the secret injection and the log group creation"
}
output "execution_role_name" {
  value       = aws_iam_role.ecs_task_execution_role.name
  description = "Generated name of the task execution role"
}
output "role_arns_for_pass_role" {
  value       = [aws_iam_role.ecs_task_role.arn, aws_iam_role.ecs_task_execution_role.arn]
  description = "Both role ARNs, for a CodePipeline policy that needs iam:PassRole scoped to the roles a registered task definition may name. Without this scoping that statement is iam:PassRole on \"*\", which is effectively privilege escalation to any role in the account that trusts ecs-tasks.amazonaws.com (rules.md A-5)"
}
